-- ============================================================
-- 02_weekly_severity.sql
-- Question: At weekly resolution, is the volume of conflict in
--           Ukraine (2026) changing, and is its CHARACTER changing?
--
-- Method:   Weekly buckets via date_trunc('week', ...) (ISO weeks,
--           Monday start). Two severity reads per week:
--             sum(weight) = volume-of-threat (count x severity)
--             avg(weight) = character-of-threat (composition,
--                           independent of volume)
--           Divergence matters: falling sum with rising avg means
--           fewer but nastier events (concentration) - often the
--           most dangerous signature.
--
-- Concepts exercised: weekly date_trunc, sum vs. avg of the same
--           column, composite-key JOIN, half-open date range
--           (>= start AND < end).
--
-- Caveats:
--   * PROVISIONAL DATA: all 2026 rows are UCDP Candidate (monthly,
--     provisional) releases - less complete than final GED.
--   * MONTHLY ROLL-UPS: weekly fatality spikes land in whichever
--     week contains the 1st of a month, because UCDP's aggregated
--     attrition events are anchored to period start dates. The
--     fatality column is therefore a calendar artifact at weekly
--     resolution; event counts carry the real weekly signal.
--   * PARTIAL EDGE WEEKS: the first bucket is truncated by the
--     date filter and the last by the end of available data. Low
--     values in boundary weeks are artifacts - trim or flag them,
--     and never read the final week's drop as a real decline.
--   * FLAT avg_severity: UCDP-Ukraine events are nearly all
--     state-based conflict (weight 5.0), so avg_severity is inert
--     on this source; it becomes informative on multi-type sources.
-- ============================================================

SELECT date_trunc('week', e.event_date)::date AS week,
       count(*) AS events,
       sum(e.fatalities) AS fatalities,
       round(sum(w.weight), 1) AS severity_score,
       round(avg(w.weight), 2) AS avg_severity
FROM events e
JOIN event_type_weights w
  ON w.source = e.source
 AND w.event_type = e.event_type
WHERE e.source = 'UCDP_GED'
  AND e.country = 'Ukraine'
  AND e.event_date >= DATE '2026-01-01'
  AND e.event_date < DATE '2027-01-01'
GROUP BY date_trunc('week', e.event_date)
ORDER BY week;
