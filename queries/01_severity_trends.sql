-- ============================================================
-- 01_severity_trends.sql
-- Question: How has the severity-weighted threat picture evolved
--           month over month, by country?
--
-- Method:   Events are weighted by analyst-assigned severity
--           (event_type_weights; rationale documented per type),
--           then aggregated into monthly buckets per country.
--           severity_score = sum of weights (volume x severity);
--           compare against raw event count and fatalities.
--
-- Concepts exercised: date_trunc() bucketing, composite-key JOIN
--           (source, event_type), GROUP BY on an expression,
--           aggregate functions.
--
-- Caveats:
--   * CURATED/PROVISIONAL SEAM: GED final data is authoritative
--     through 2025-12-31; 2026 rows come from monthly Candidate
--     releases, which are provisional and less complete. The sharp
--     drop in event counts at Jan 2026 is a coverage artifact of
--     this seam, NOT a real de-escalation. Do not interpret trends
--     across the boundary without flagging it.
--   * AGGREGATE EVENTS: UCDP records some front-line attrition as
--     roll-up events spanning a sector and period, anchored to the
--     period start date (e.g. the 1st of a month). Monthly fatality
--     totals mix discrete incidents with these roll-ups, so event
--     counts are the more stable trend indicator than fatalities.
--   * WEIGHT DISCRIMINATION: within UCDP, organized-violence types
--     cluster at high weights, so severity_score closely tracks
--     5 x events here. The weighting adds analytic value mainly for
--     multi-type sources (e.g. ACLED protests vs. battles).
--   * INNER JOIN AS FILTER: events whose (source, event_type) has
--     no row in event_type_weights are silently dropped. Keep the
--     weights table in sync when adding sources.
-- ============================================================

SELECT date_trunc('month', e.event_date)::date AS month,
       e.country,
       count(*) AS events,
       sum(e.fatalities) AS fatalities,
       round(sum(w.weight), 1) AS severity_score
FROM events e
JOIN event_type_weights w
  ON w.source = e.source
 AND w.event_type = e.event_type
WHERE e.source = 'UCDP_GED'
  AND e.event_date >= DATE '2025-01-01'
GROUP BY date_trunc('month', e.event_date), e.country
ORDER BY month, severity_score DESC;
