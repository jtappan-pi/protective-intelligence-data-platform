-- ============================================================
-- 04_travel_threat_assessment.sql
-- Question: For each UPCOMING executive trip, what conflict/unrest
--           activity occurred within 100 km of the destination in
--           the 90 days before arrival - and can we trust a zero?
--
-- Method:   executive_travel LEFT JOINed to events on BOTH a
--           distance condition (haversine <= 100 km) and a
--           per-trip date window (half-open: the 90 days ending
--           the day before start_date), aggregated to one row per
--           trip. GROUP BY includes the primary key (travel_id) so
--           trips can never merge on coincidental name/city
--           matches. A country-level coverage subquery
--           distinguishes "monitored and quiet" from "not
--           monitored at all".
--
-- Concepts exercised: LEFT JOIN with compound (distance + date)
--           conditions in ON; per-row anchored date windows
--           (t.start_date - 90, half-open); COUNT(col) vs COUNT(*)
--           and COALESCE(SUM...) NULL handling; correlated scalar
--           subquery (coverage check, and the commented
--           alternative formulation); subquery-vs-join
--           equivalence.
--
-- Why the JOIN form is primary: it scans events once regardless of
--           how many metrics are computed. The correlated-subquery
--           alternative (bottom) re-scans events once per metric
--           per trip - more readable per column, but costlier as
--           trips or metrics grow. Both produce identical results.
--
-- Caveats:
--   * A ZERO IS NOT SAFETY: events_90d = 0 cannot, by itself,
--     distinguish a quiet destination from an UNMONITORED one.
--     country_events_all_time = 0 means no source currently loads
--     that country (e.g. DR Congo, Egypt at time of writing) and
--     the trip row should be read as NO COVERAGE, not low threat.
--     Absence of data is not absence of threat.
--   * Current results include synthetic TEST fixtures (source =
--     'TEST') used for query validation; production runs should
--     filter or have retired them.
--   * Inherited limitations: event coordinates carry provider
--     geocoding precision (events without coordinates never match
--     a distance join); event_date is the provider's start/anchor
--     date; 2026 UCDP rows are provisional Candidate data; UCDP
--     scope excludes protests/riots.
--   * 100 km and 90 days are provisional analytic choices, to be
--     tuned per protective-intelligence requirements.
-- ============================================================

SELECT t.traveler_name,
       t.traveler_role,
       t.dest_city,
       t.dest_country,
       t.start_date,
       t.end_date,
       count(e.event_id) AS events_90d,
       coalesce(sum(e.fatalities), 0) AS fatalities_90d,
       max(e.event_date) AS latest_event,
       -- Coverage check: any events ever ingested for this country?
       -- 0 here means the destination is NOT MONITORED; events_90d
       -- is then "no data", not "no threat".
       (SELECT count(*)
          FROM events c
         WHERE c.country = t.dest_country) AS country_events_all_time
FROM executive_travel t
LEFT JOIN events e
    ON haversine_km(t.latitude, t.longitude, e.latitude, e.longitude) <= 100
   AND e.event_date >= t.start_date - 90
   AND e.event_date <  t.start_date
WHERE t.start_date >= CURRENT_DATE
GROUP BY t.travel_id, t.traveler_name, t.traveler_role,
         t.dest_city, t.dest_country, t.start_date, t.end_date
ORDER BY t.start_date;

-- ------------------------------------------------------------
-- Equivalent correlated-subquery formulation (reference).
-- Identical output; re-scans events once per metric per trip, so
-- the JOIN form above is preferred as trips/metrics grow.
-- ------------------------------------------------------------
-- SELECT t.traveler_name,
--        t.traveler_role,
--        t.dest_city,
--        t.dest_country,
--        t.start_date,
--        (SELECT count(*)
--           FROM events e
--          WHERE haversine_km(t.latitude, t.longitude,
--                             e.latitude, e.longitude) <= 100
--            AND e.event_date >= t.start_date - 90
--            AND e.event_date <  t.start_date) AS events_90d,
--        (SELECT coalesce(sum(e.fatalities), 0)
--           FROM events e
--          WHERE haversine_km(t.latitude, t.longitude,
--                             e.latitude, e.longitude) <= 100
--            AND e.event_date >= t.start_date - 90
--            AND e.event_date <  t.start_date) AS fatalities_90d
-- FROM executive_travel t
-- WHERE t.start_date >= CURRENT_DATE
-- ORDER BY t.start_date;
