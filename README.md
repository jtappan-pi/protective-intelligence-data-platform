# Protective Intelligence Data Platform

A PostgreSQL-based conflict-event analysis platform demonstrating GSOC/protective-intelligence
analytics in SQL: facility proximity analysis, severity-weighted trends, escalation flagging,
and pre-travel threat assessment.

---

## BLUF

This project implements an end-to-end protective intelligence data pipeline: real, licensed
conflict-event data (UCDP) is ingested into a source-agnostic PostgreSQL schema and analyzed
against a **fictional** corporate footprint (facilities and executive travel) through a
progression of documented SQL analytics. It was built by a career all-source intelligence
analyst transitioning to protective and threat intelligence roles in corporate security, to make a decade of analytic
tradecraft demonstrable in open tooling. All company data is invented; all event data is
public and used within its license; the repository contains code, schema, queries, and
methodology — never raw event data.

**Key caveats up front:** event coverage is source-bounded (UCDP records organized violence
only — no protests or riots), 2026 data is provisional, and a zero in any output means
"no recorded events," which is not the same as "no threat." See [Limitations](#limitations).

## Architecture

```
UCDP GED / Candidate (CSV)          ACLED (API; see note)
            \                          /
             Python ingest modules (idempotent upserts)
                          |
             PostgreSQL 16 + PostGIS (Docker)
     facilities | executive_travel | events | event_type_weights
                          |
             SQL analytics (queries/01-04)
                          |
             Streamlit dashboard (planned)
```

Design decisions:

- **Source-agnostic events schema.** Providers are identified by a `source` column; uniqueness
  is enforced on `(source, source_event_id)`; only fields common to conflict-event datasets are
  promoted to columns. Adding a source is a new mapper module, not a schema migration — a
  property that was exercised in practice when the primary source changed mid-build.
- **Idempotent ingestion.** Every load is an upsert (`ON CONFLICT ... DO UPDATE`); re-running
  a load is always safe and picks up provider revisions.
- **Raw data never touches the repository.** Event data flows source → memory → a Docker
  named volume. The `data/` directory and `.env` are gitignored; `.env.example` documents
  required configuration with placeholders.
- **Analytic judgment stored as data.** Severity weights live in a lookup table with a
  written `rationale` per event type — transparent, tunable, and queryable.
- **Plain-SQL geospatial first.** Distance math is an explicit haversine function so every
  line is explainable; the production upgrade path (PostGIS `geography` + spatial indexes)
  is one extension away and deliberately deferred.

## Quick start

Requires Docker Desktop and Python 3.11+.

```bash
git clone https://github.com/jtappan-pi/protective-intelligence-data-platform.git
cd protective-intelligence-data-platform
cp .env.example .env        # review values; host port defaults per docker-compose.yml
docker compose up -d        # builds schema + fictional footprint on first start
pip install -r requirements.txt

# Download UCDP GED and Candidate CSVs from https://ucdp.uu.se/downloads/ into data/
python ingest/ucdp_ingest.py --csv data/GEDEvent_v26_1.csv --countries "Georgia,Armenia,Azerbaijan,Ukraine"
python ingest/ucdp_ingest.py --csv "data/GEDEvent_v26_0*.csv" --countries "Georgia,Armenia,Azerbaijan,Ukraine" --since 2026-01-01

# Run an analysis
docker exec -i pi_platform_db psql -U pi_analyst -d pi_platform < queries/01_severity_trends.sql
```

## Data sources & licensing

**UCDP (primary).** Uppsala Conflict Data Program Georeferenced Event Dataset (GED) and
Candidate Events Dataset, used under **CC BY 4.0**. Required citations:

- Shawn Davies, Therése Pettersson, Magnus Öberg, Organized violence 1989–2025, and violent political protests, Journal of Peace Research, 2026. https://doi.org/10.1093/jopres/xjag046
- Sundberg, Ralph and Erik Melander (2013) Introducing the UCDP Georeferenced Event Dataset. Journal of Peace Research 50(4).
- Hegre, Håvard et al. (2020). "Introducing the UCDP Candidate Events Dataset."
  *Research & Politics* 7(3).

**ACLED (planned/secondary).** The platform was designed with ACLED as a source and retains a
compatible ingest module and severity weights. ACLED event-level API access moved to paid
tiers in 2026; the Open tier provides aggregated weekly data, which is on the roadmap as a
complementary (non-geolocated) table. No ACLED data is redistributed here.

**Source precedence rule:** curated releases are authoritative through their documented
coverage boundary (GED v26.1: 2025-12-31); provisional Candidate data backfills only beyond
that seam. Boundaries are set by documentation, never inferred from observed data.

## Query progression

| File | Analytical question | SQL concepts |
|---|---|---|
| `queries/01_severity_trends.sql` | How has the severity-weighted threat picture evolved monthly, by country? | `date_trunc` bucketing, composite-key JOIN, aggregation |
| `queries/02_weekly_severity.sql` | Is conflict volume changing — and is its *character* changing? | sum vs. avg of weights, half-open date ranges |
| `queries/03_escalation_flags.sql` | Which weeks merit analyst attention, at what confidence? | CTEs, window functions (`LAG`, framed moving average), tiered `CASE` |
| `queries/04_travel_threat_assessment.sql` | What happened near each upcoming executive trip in the prior 90 days — and can we trust a zero? | correlated subqueries, subquery/JOIN equivalence, per-row date windows |

Each file carries a header documenting its question, method, and caveats. Supporting schema
analytics (distance joins, `LEFT JOIN` NULL handling) live in `sql/01_schema.sql` and the
seeded footprint.

## Methodology

- **Severity weighting** converts heterogeneous event types into a comparable score; weights
  are analyst judgments recorded with rationale in `event_type_weights` and are deliberately
  tunable. Within UCDP data, organized-violence types cluster at high weights, so weighting
  adds discrimination mainly when multi-type sources (e.g., ACLED) are present.
- **Tiered escalation flags** (WATCH / ESCALATION / DECLINE) trade detection latency against
  false-alarm rate explicitly: single-week spikes cue a low-confidence look; only consecutive
  spikes escalate. Thresholds (±25%, two-week persistence, 4-week moving average) are
  provisional pending consumer tuning. Flags cue analyst review and are intended for fusion
  with other reporting streams; they do not replace analyst judgment.
- **Event counts over fatality sums** for trend reads, because provider fatality totals mix
  discrete incidents with period-anchored aggregate events (see Limitations).

## Limitations

- **Coverage seam.** The sharp drop in 2026 event counts reflects the GED→Candidate
  transition (curated vs. provisional data), not de-escalation. Trends are never interpreted
  across this boundary without flagging it.
- **Aggregate roll-up events.** UCDP records some front-line attrition as single events
  spanning a sector and period, anchored to the period start date (often the 1st of a month)
  and sometimes without coordinates. Fatality sums inherit these placements; weekly fatality
  spikes land in whichever week contains a month boundary.
- **A zero is not safety.** Proximity results of zero cannot distinguish a quiet destination
  from an unmonitored one. Query 04 carries an explicit per-country coverage check; countries
  with no ingested source report NO COVERAGE, not low threat.
- **Scope.** UCDP covers organized violence only — no protests or riots. The 2024–26 Caucasus
  data illustrates this concretely: sustained civil unrest in the region produces no
  qualifying events. Unrest coverage (ACLED aggregates / GDELT) is a roadmap item.
- **Precision inheritance.** Event coordinates carry provider geocoding precision (events
  without coordinates never match distance joins); `event_date` is the provider's start/anchor
  date, so multi-day events collapse to day one; UCDP fatality figures use the `best`
  estimate (low/high bounds not currently represented).
- **Synthetic fixtures.** A small set of clearly-labeled test events (`source = 'TEST'`) is
  used to validate spatial/temporal query logic and appears in some documented outputs.
- **Geospatial method.** Great-circle (haversine) distance in plain SQL, accurate to ~0.5%;
  PostGIS `ST_DWithin` with spatial indexing is the documented production path.

## Roadmap

1. ACLED aggregated weekly data as a complementary unrest-trend table (Open-tier compliant)
2. Streamlit dashboard over the query progression
3. PostGIS migration for indexed spatial joins
4. GDELT evaluation for event-level unrest coverage
5. Calendar-spine time series (gap-safe window functions)

---

*All corporate entities, personnel, facilities, and itineraries in this repository are
fictional. Event data © their respective providers, used under license; no raw event data is
redistributed.*
