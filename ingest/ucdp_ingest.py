"""
UCDP ingestion: GED / Candidate CSV -> local Postgres.

Why a CSV loader instead of an API client:
  * UCDP's bulk downloads (https://ucdp.uu.se/downloads/) are free, require
    no account, and are licensed CC BY 4.0 (reuse allowed with citation).
  * UCDP's API exists but requires a token granted by the maintainers;
    the CSV path works today with zero gatekeeping.
  * This demonstrates the second ingest pattern every data platform needs:
    file-based batch loads (vs. acled_ingest.py's API pattern).

Source files (put them in data/, which is gitignored):
  * GED Global <ver>.csv (zip ok)        -- final, curated; through end of last year
  * UCDP Candidate Events <ver>.csv ...  -- monthly provisional; covers recent months

Mapping notes (interview-defensible):
  * UCDP's taxonomy is type_of_violence {1,2,3}; we map to readable labels
    and store them in event_type, consistent with how ACLED's taxonomy
    occupies the same column. The `source` column is what keeps the two
    taxonomies from being confused with each other.
  * fatalities = UCDP's `best` estimate (they also publish low/high bounds).
  * UCDP covers ORGANIZED VIOLENCE only - no protests/riots. Document this
    as a coverage limitation in the README; it is the key analytic
    difference vs. ACLED.
  * Same idempotent upsert contract on (source, source_event_id): loading
    GED and Candidate files that overlap, or reloading after a new monthly
    release, never duplicates events.

Usage:
    python ingest/ucdp_ingest.py --csv data/GEDEvent_v26_1.csv --countries "Georgia,Armenia,Azerbaijan"
    python ingest/ucdp_ingest.py --csv data/ucdp-candidate-*.csv --countries "Georgia,Armenia,Azerbaijan" --since 2026-01-01
"""

import argparse
import csv
import glob
import io
import os
import sys
import zipfile
from datetime import date

import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

SOURCE = "UCDP_GED"

VIOLENCE_TYPES = {
    "1": "State-based conflict",
    "2": "Non-state conflict",
    "3": "One-sided violence",
}

UPSERT_SQL = """
    INSERT INTO events (
        source, source_event_id, event_date, event_type, sub_event_type,
        actor1, actor2, country, admin1, location_name,
        latitude, longitude, fatalities, notes
    )
    VALUES %s
    ON CONFLICT (source, source_event_id) DO UPDATE SET
        event_date     = EXCLUDED.event_date,
        event_type     = EXCLUDED.event_type,
        sub_event_type = EXCLUDED.sub_event_type,
        actor1         = EXCLUDED.actor1,
        actor2         = EXCLUDED.actor2,
        country        = EXCLUDED.country,
        admin1         = EXCLUDED.admin1,
        location_name  = EXCLUDED.location_name,
        latitude       = EXCLUDED.latitude,
        longitude      = EXCLUDED.longitude,
        fatalities     = EXCLUDED.fatalities,
        notes          = EXCLUDED.notes,
        ingested_at    = now()
"""


def open_csv_rows(path: str):
    """Yield dict rows from a .csv file, or from the first .csv inside a .zip."""
    if path.lower().endswith(".zip"):
        with zipfile.ZipFile(path) as zf:
            inner = next(n for n in zf.namelist() if n.lower().endswith(".csv"))
            with zf.open(inner) as fh:
                yield from csv.DictReader(io.TextIOWrapper(fh, encoding="utf-8-sig"))
    else:
        with open(path, newline="", encoding="utf-8-sig") as fh:
            yield from csv.DictReader(fh)


def to_row(rec: dict) -> tuple | None:
    """Map one UCDP GED/Candidate record to the normalized events schema."""
    def num(v):
        try:
            return float(v)
        except (TypeError, ValueError):
            return None

    event_date = (rec.get("date_start") or "")[:10]  # 'YYYY-MM-DD hh:mm:ss' -> date
    if not event_date:
        return None

    return (
        SOURCE,
        rec["id"],
        event_date,
        VIOLENCE_TYPES.get(rec.get("type_of_violence", ""), "Unknown"),
        rec.get("dyad_name") or None,
        rec.get("side_a") or None,
        rec.get("side_b") or None,
        rec.get("country") or "Unknown",
        rec.get("adm_1") or None,
        rec.get("where_description") or None,
        num(rec.get("latitude")),
        num(rec.get("longitude")),
        int(float(rec.get("best") or 0)),
        rec.get("conflict_name") or None,
    )


def main():
    load_dotenv()

    parser = argparse.ArgumentParser(description="Ingest UCDP GED/Candidate CSVs into Postgres")
    parser.add_argument("--csv", required=True, nargs="+",
                        help="Path(s) to UCDP csv/zip files; globs ok (data/*.csv)")
    parser.add_argument("--countries", default=None,
                        help="Optional comma-separated filter, e.g. 'Georgia,Armenia,Azerbaijan'")
    parser.add_argument("--since", default=None,
                        help="Optional ISO date; skip events before it (e.g. 2024-01-01)")
    args = parser.parse_args()

    paths = []
    for pattern in args.csv:
        paths.extend(glob.glob(pattern) or [pattern])
    missing = [p for p in paths if not os.path.exists(p)]
    if missing:
        sys.exit(f"File(s) not found: {missing}\n"
                 "Download GED/Candidate CSVs from https://ucdp.uu.se/downloads/ into data/")

    countries = None
    if args.countries:
        countries = {c.strip().lower() for c in args.countries.split(",") if c.strip()}
    since = date.fromisoformat(args.since) if args.since else None

    conn = psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        dbname=os.environ.get("POSTGRES_DB", "pi_platform"),
        user=os.environ.get("POSTGRES_USER", "pi_analyst"),
        password=os.environ.get("POSTGRES_PASSWORD", "changeme"),
    )

    total = kept = 0
    batch = []
    try:
        with conn, conn.cursor() as cur:
            def flush():
                if batch:
                    psycopg2.extras.execute_values(cur, UPSERT_SQL, batch, page_size=1000)
                    batch.clear()

            for path in paths:
                print(f"Reading {path} ...")
                for rec in open_csv_rows(path):
                    total += 1
                    if countries and (rec.get("country") or "").lower() not in countries:
                        continue
                    row = to_row(rec)
                    if row is None:
                        continue
                    if since and date.fromisoformat(row[2]) < since:
                        continue
                    batch.append(row)
                    kept += 1
                    if len(batch) >= 5000:
                        flush()
                        print(f"  ... {kept} events upserted so far")
            flush()
    finally:
        conn.close()

    print(f"Done. Scanned {total} rows, upserted {kept} events (source={SOURCE}).")


if __name__ == "__main__":
    main()
