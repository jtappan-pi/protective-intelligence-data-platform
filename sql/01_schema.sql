-- ============================================================
-- Protective Intelligence Data Platform — core schema
-- All company data is FICTIONAL. Event data is ingested locally
-- from licensed sources (ACLED Open tier) and is NOT redistributed.
-- ============================================================

-- ------------------------------------------------------------
-- 1. FACILITIES — the fictional company footprint
-- ------------------------------------------------------------
CREATE TABLE facilities (
    facility_id   SERIAL PRIMARY KEY,        -- surrogate key; auto-incrementing
    facility_code TEXT NOT NULL UNIQUE,      -- human-readable natural key, e.g. 'TBS-01'
    name          TEXT NOT NULL,
    facility_type TEXT NOT NULL,             -- 'regional_hq' | 'office' | 'logistics' | 'datacenter'
    city          TEXT NOT NULL,
    country       TEXT NOT NULL,
    region        TEXT NOT NULL,             -- company's own regional taxonomy
    latitude      NUMERIC(9,6) NOT NULL,     -- NUMERIC, not FLOAT: exact decimal storage
    longitude     NUMERIC(9,6) NOT NULL,
    headcount     INTEGER,
    criticality   SMALLINT NOT NULL DEFAULT 2
                  CHECK (criticality BETWEEN 1 AND 3),  -- 1 = highest
    opened_date   DATE
);

-- ------------------------------------------------------------
-- 2. EXECUTIVE TRAVEL — fictional itineraries to score against events
-- ------------------------------------------------------------
CREATE TABLE executive_travel (
    travel_id     SERIAL PRIMARY KEY,
    traveler_name TEXT NOT NULL,             -- fictional persons only
    traveler_role TEXT NOT NULL,
    facility_id   INTEGER REFERENCES facilities(facility_id),  -- NULL if not visiting a company site
    dest_city     TEXT NOT NULL,
    dest_country  TEXT NOT NULL,
    latitude      NUMERIC(9,6) NOT NULL,
    longitude     NUMERIC(9,6) NOT NULL,
    start_date    DATE NOT NULL,
    end_date      DATE NOT NULL,
    purpose       TEXT,
    CHECK (end_date >= start_date)
);

-- ------------------------------------------------------------
-- 3. EVENTS — SOURCE-AGNOSTIC normalized event store
--    ACLED today; GDELT / UCDP GED can slot in later because:
--      * `source` identifies the provider
--      * (source, source_event_id) is the uniqueness contract
--      * only fields common to conflict-event datasets are promoted
--        to real columns; anything provider-specific stays in raw_attrs
-- ------------------------------------------------------------
CREATE TABLE events (
    event_id        BIGSERIAL PRIMARY KEY,
    source          TEXT NOT NULL,                  -- 'ACLED' | 'GDELT' | 'UCDP_GED'
    source_event_id TEXT NOT NULL,                  -- provider's own ID (ACLED event_id_cnty)
    event_date      DATE NOT NULL,
    event_type      TEXT NOT NULL,                  -- provider taxonomy, e.g. 'Riots'
    sub_event_type  TEXT,
    actor1          TEXT,
    actor2          TEXT,
    country         TEXT NOT NULL,
    admin1          TEXT,                           -- first-level admin division
    location_name   TEXT,
    latitude        NUMERIC(9,6),
    longitude       NUMERIC(9,6),
    fatalities      INTEGER DEFAULT 0,
    notes           TEXT,
    raw_attrs       JSONB,          -- provider-specific extras; LOCAL DB ONLY, never in repo
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- One row per provider event. This constraint is what makes
    -- re-running ingestion safe (idempotent upserts) and lets multiple
    -- sources coexist without ID collisions.
    CONSTRAINT uq_events_source_id UNIQUE (source, source_event_id)
);

-- Indexes chosen for the query patterns we know are coming:
CREATE INDEX idx_events_date    ON events (event_date);
CREATE INDEX idx_events_country ON events (country, event_date);
CREATE INDEX idx_events_type    ON events (event_type);

-- ------------------------------------------------------------
-- 4. SEVERITY WEIGHTS — analytic judgment as DATA, not hard-coded CASE logic
--    A lookup table means: (a) weights are transparent and tunable,
--    (b) you practice another JOIN, (c) methodology is documentable
--    in the README like a real intel product.
-- ------------------------------------------------------------
CREATE TABLE event_type_weights (
    source     TEXT NOT NULL,
    event_type TEXT NOT NULL,
    weight     NUMERIC(4,2) NOT NULL,
    rationale  TEXT,
    PRIMARY KEY (source, event_type)
);

INSERT INTO event_type_weights (source, event_type, weight, rationale) VALUES
('ACLED', 'Battles',                      5.0, 'Armed clash; highest direct threat to life/operations'),
('ACLED', 'Explosions/Remote violence',   5.0, 'IED/shelling/air strikes; indiscriminate lethality'),
('ACLED', 'Violence against civilians',   4.0, 'Direct targeting of non-combatants'),
('ACLED', 'Riots',                        3.0, 'Violent demonstrations; property/mobility risk'),
('ACLED', 'Protests',                     1.5, 'Usually peaceful; disruption and escalation potential'),
('ACLED', 'Strategic developments',       1.0, 'Contextual indicator, rarely a direct threat');

-- ------------------------------------------------------------
-- 5. Distance helper — great-circle (haversine) distance in km.
--    Written in plain SQL deliberately: you should be able to explain
--    every line. In production you'd use PostGIS ST_DWithin with a
--    geography type + spatial index; that upgrade is Phase 3.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION haversine_km(
    lat1 NUMERIC, lon1 NUMERIC,
    lat2 NUMERIC, lon2 NUMERIC
) RETURNS NUMERIC
LANGUAGE SQL IMMUTABLE AS $$
    SELECT 6371 * 2 * asin(
        sqrt(
            sin(radians((lat2 - lat1) / 2))^2 +
            cos(radians(lat1)) * cos(radians(lat2)) *
            sin(radians((lon2 - lon1) / 2))^2
        )
    )::NUMERIC
$$;
