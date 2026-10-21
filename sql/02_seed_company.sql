-- ============================================================
-- Seed data: FICTIONAL company footprint for "Meridian Atlas Group"
-- (invented multinational). No real company, no real people.
-- Coordinates are city-center approximations — fine for a fictional
-- footprint; precision matters for events, not for made-up offices.
-- ============================================================

INSERT INTO facilities
(facility_code, name, facility_type, city, country, region, latitude, longitude, headcount, criticality, opened_date) VALUES
-- Eurasia (primary AOR)
('TBS-01', 'Tbilisi Regional HQ',        'regional_hq', 'Tbilisi',     'Georgia',    'Eurasia',        41.7151,  44.8271, 220, 1, '2015-03-01'),
('EVN-01', 'Yerevan Engineering Office', 'office',      'Yerevan',     'Armenia',    'Eurasia',        40.1792,  44.4991,  85, 2, '2018-09-15'),
('GYD-01', 'Baku Logistics Hub',         'logistics',   'Baku',        'Azerbaijan', 'Eurasia',        40.4093,  49.8671, 140, 1, '2016-06-01'),
('ALA-01', 'Almaty Office',              'office',      'Almaty',      'Kazakhstan', 'Eurasia',        43.2220,  76.8512,  60, 2, '2019-11-01'),
('IST-01', 'Istanbul Datacenter',        'datacenter',  'Istanbul',    'Turkey',     'Eurasia',        41.0082,  28.9784,  45, 1, '2017-02-01'),
-- MENA / North Africa
('CAI-01', 'Cairo Regional Office',      'office',      'Cairo',       'Egypt',      'MENA',           30.0444,  31.2357, 110, 2, '2014-05-01'),
('TUN-01', 'Tunis Support Center',       'office',      'Tunis',       'Tunisia',    'MENA',           36.8065,  10.1815,  70, 3, '2020-01-15'),
-- Central Africa
('FIH-01', 'Kinshasa Field Office',      'office',      'Kinshasa',    'DR Congo',   'Central Africa', -4.4419,  15.2663,  35, 2, '2021-04-01'),
-- LATAM
('MEX-01', 'Mexico City Regional HQ',    'regional_hq', 'Mexico City', 'Mexico',     'LATAM',          19.4326, -99.1332, 180, 1, '2013-08-01'),
('BOG-01', 'Bogota Office',              'office',      'Bogota',      'Colombia',   'LATAM',           4.7110, -74.0721,  90, 2, '2017-10-01');

-- ------------------------------------------------------------
-- Fictional executive travel. Mix of:
--   * visits to company facilities (facility_id set)
--   * non-facility destinations (facility_id NULL) so your queries
--     must handle both cases — that's intentional.
-- Dates straddle "recent past / near future" so travel-vs-events
-- queries have something to bite on. Adjust to stay near the
-- current date when you rebuild the DB.
-- ------------------------------------------------------------
INSERT INTO executive_travel
(traveler_name, traveler_role, facility_id, dest_city, dest_country, latitude, longitude, start_date, end_date, purpose) VALUES
('Dana Okafor',   'CEO',
    (SELECT facility_id FROM facilities WHERE facility_code='TBS-01'),
    'Tbilisi', 'Georgia', 41.7151, 44.8271, '2026-10-12', '2026-10-15', 'Regional leadership summit'),
('Dana Okafor',   'CEO', NULL,
    'Batumi', 'Georgia', 41.6168, 41.6367, '2026-10-16', '2026-10-17', 'Investor site visit'),
('Marta Reyes',   'COO',
    (SELECT facility_id FROM facilities WHERE facility_code='MEX-01'),
    'Mexico City', 'Mexico', 19.4326, -99.1332, '2026-10-05', '2026-10-08', 'Quarterly ops review'),
('Marta Reyes',   'COO', NULL,
    'Monterrey', 'Mexico', 25.6866, -100.3161, '2026-10-09', '2026-10-10', 'Supplier negotiations'),
('Ilya Bergman',  'CFO',
    (SELECT facility_id FROM facilities WHERE facility_code='GYD-01'),
    'Baku', 'Azerbaijan', 40.4093, 49.8671, '2026-11-02', '2026-11-05', 'Logistics expansion review'),
('Amina Diallo',  'Chief Security Officer',
    (SELECT facility_id FROM facilities WHERE facility_code='FIH-01'),
    'Kinshasa', 'DR Congo', -4.4419, 15.2663, '2026-10-20', '2026-10-24', 'Field office security assessment'),
('Ilya Bergman',  'CFO', NULL,
    'Astana', 'Kazakhstan', 51.1605, 71.4704, '2026-09-22', '2026-09-24', 'Government relations'),
('Dana Okafor',   'CEO',
    (SELECT facility_id FROM facilities WHERE facility_code='CAI-01'),
    'Cairo', 'Egypt', 30.0444, 31.2357, '2026-11-10', '2026-11-12', 'MENA strategy review');
