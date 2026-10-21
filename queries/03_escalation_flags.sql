-- ============================================================
-- 03_escalation_flags.sql
-- Question: Which weeks show ESCALATION in Ukraine conflict
--           activity that merits analyst attention, and at what
--           confidence level?
--
-- Method:   Weekly event counts (CTE) with window functions:
--             * LAG(events)      -> week-over-week comparison
--             * LAG(events, 2)   -> two-week lookback for the
--                                   consecutive-spike test
--             * 4-week moving average (window frame: ROWS BETWEEN
--               3 PRECEDING AND CURRENT ROW) -> regime-level trend
--           Tiered alerting (CASE, evaluated top-down):
--             NO BASELINE  first week; no prior row to compare
--             ESCALATION   two consecutive >= +25% weekly spikes
--             WATCH        single >= +25% spike (low confidence)
--             DECLINE      >= -25% weekly drop
--             STABLE       within +/- 25% of prior week
--           Alert doctrine: flags CUE analyst review and are fused
--           with other reporting streams; they do not replace
--           analyst judgment. Thresholds (25%, 2-week persistence,
--           4-week frame) are provisional analytic choices to be
--           tuned against consumer feedback and observed
--           false-alarm/latency rates.
--
-- Concepts exercised: CTE (WITH), window functions (LAG with
--           offset, AVG OVER with an explicit frame), ordered
--           CASE logic, NULLIF divide-by-zero guard, NULL
--           three-valued logic (the NO BASELINE branch).
--
-- Caveats:
--   * BOUNDARY-WEEK ARTIFACTS: the first week in range is
--     truncated by the date filter and the last by the end of
--     available data. Flags computed against them are artifacts
--     (e.g. a WATCH off the partial first week; a large DECLINE
--     in the final partial week). Retained and documented here
--     rather than filtered, so the behavior stays visible;
--     a production version would exclude partial boundary weeks
--     before flagging.
--   * LAG = PRIOR WEEK ONLY IF GAPLESS: LAG reads the previous
--     ROW, which equals the previous WEEK only when no week is
--     absent (a zero-event week produces no row). Verified
--     gapless for Ukraine 2026 (consecutive Mondays, 36 rows);
--     a calendar spine join is the general fix if coverage
--     changes.
--   * PROVISIONAL DATA: all 2026 rows are UCDP Candidate
--     (monthly, provisional) releases.
--   * Trade-off by design: raw weekly flags minimize detection
--     latency at the cost of false alarms; the 4-week average
--     suppresses noise at the cost of latency. The tiers spend
--     analyst attention accordingly (WATCH = cheap look,
--     ESCALATION = persistent signal).
-- ============================================================

WITH weekly AS (
    SELECT date_trunc('week', e.event_date)::date AS week,
           count(*) AS events
    FROM events e
    WHERE e.source = 'UCDP_GED'
      AND e.country = 'Ukraine'
      AND e.event_date >= DATE '2026-01-01'
      AND e.event_date < DATE '2027-01-01'
    GROUP BY date_trunc('week', e.event_date)
)
SELECT week,
       events,
       LAG(events) OVER (ORDER BY week) AS prev_events,
       round(avg(events) OVER (ORDER BY week ROWS BETWEEN 3 PRECEDING AND CURRENT ROW), 1) AS events_4wk_avg,
       round(100.0 * (events - LAG(events) OVER (ORDER BY week))
             / NULLIF(LAG(events) OVER (ORDER BY week), 0), 1) AS wow_pct,
       CASE
           WHEN LAG(events) OVER (ORDER BY week) IS NULL THEN 'NO BASELINE'
           WHEN events >= 1.25 * LAG(events) OVER (ORDER BY week)
            AND LAG(events) OVER (ORDER BY week) >= 1.25 * LAG(events, 2) OVER (ORDER BY week)
               THEN 'ESCALATION'          -- two consecutive spikes
           WHEN events >= 1.25 * LAG(events) OVER (ORDER BY week)
               THEN 'WATCH'               -- single spike, low confidence
           WHEN events <= 0.75 * LAG(events) OVER (ORDER BY week)
               THEN 'DECLINE'
           ELSE 'STABLE'
       END AS flag
FROM weekly
ORDER BY week;
