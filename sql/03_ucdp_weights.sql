-- Severity weights for UCDP GED event types.
-- Runs automatically on a FRESH database build (docker compose down -v && up).
-- On your EXISTING database, run it once by hand:
--   docker exec -i pi_platform_db psql -U pi_analyst -d pi_platform < sql/03_ucdp_weights.sql
-- ON CONFLICT makes it safe to run repeatedly (same idempotency idea as ingestion).

INSERT INTO event_type_weights (source, event_type, weight, rationale) VALUES
('UCDP_GED', 'State-based conflict', 5.0, 'Government-vs-armed-group combat; highest direct threat'),
('UCDP_GED', 'Non-state conflict',   4.5, 'Armed group vs armed group; severe but less predictable geography'),
('UCDP_GED', 'One-sided violence',   4.0, 'Deliberate targeting of civilians'),
('UCDP_GED', 'Unknown',              1.0, 'Unmapped type; investigate before weighting higher')
ON CONFLICT (source, event_type) DO UPDATE SET
    weight = EXCLUDED.weight,
    rationale = EXCLUDED.rationale;
