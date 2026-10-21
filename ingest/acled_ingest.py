"""
Phase-1 ingestion: ACLED -> local Postgres.

Design notes (interview-defensible):
  * OAuth password grant against ACLED's token endpoint (the post-2025
    auth model; legacy access keys are retired). Token is valid 24h —
    plenty for a batch job, so we don't bother with the refresh flow.
  * Pagination: ACLED returns up to `limit` rows per call (Open tier:
    5,000). We loop pages until a short page comes back.
  * Idempotent loads: every row is UPSERTed on (source, source_event_id),
    so re-running the script never duplicates events and picks up
    ACLED's revisions to recent events (they revise!).
  * Source-agnostic: this file maps ACLED fields -> the normalized
    `events` schema. A GDELT or UCDP loader would be a sibling module
    with its own mapping, writing to the same table.
  * Raw API responses never touch the repo: data flows API -> memory ->
    Postgres (a Docker named volume). Nothing written to disk.

Usage:
    cp .env.example .env   # fill in credentials
    pip install -r requirements.txt
    python ingest/acled_ingest.py --countries "Georgia,Armenia,Azerbaijan" --days 90
"""

import argparse
import os
import sys
import time

import psycopg2
import psycopg2.extras
import requests
from datetime import date, timedelta

from dotenv import load_dotenv

TOKEN_URL = "https://acleddata.com/oauth/token"
DATA_URL = "https://acleddata.com/api/acled/read"
PAGE_SIZE = 5000  # ACLED Open-tier max rows per call

# Only the fields we normalize. Requesting a narrow field list is polite
# to the API and keeps you honest about what your schema actually uses.
FIELDS = "|".join([
    "event_id_cnty", "event_date", "event_type", "sub_event_type",
    "actor1", "actor2", "country", "admin1", "location",
    "latitude", "longitude", "fatalities", "notes",
])

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


def get_token(email: str, password: str) -> str:
    """Exchange myACLED credentials for a 24h bearer token."""
    resp = requests.post(
        TOKEN_URL,
        data={
            "username": email,
            "password": password,
            "grant_type": "password",
            "client_id": "acled",
        },
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def fetch_pages(token: str, countries: list[str], start: date, end: date):
    """Yield lists of raw ACLED event dicts, one page at a time."""
    headers = {"Authorization": f"Bearer {token}"}
    page = 1
    while True:
        params = {
            "_format": "json",
            "country": "|".join(countries),
            "event_date": f"{start}|{end}",
            "event_date_where": "BETWEEN",
            "fields": FIELDS,
            "limit": PAGE_SIZE,
            "page": page,
        }
        resp = requests.get(DATA_URL, headers=headers, params=params, timeout=120)
        resp.raise_for_status()
        rows = resp.json().get("data", [])
        if not rows:
            return
        print(f"  page {page}: {len(rows)} events")
        yield rows
        if len(rows) < PAGE_SIZE:
            return  # short page = last page
        page += 1
        time.sleep(1)  # be a good API citizen


def to_row(ev: dict) -> tuple:
    """Map one ACLED record to the normalized events schema."""
    def num(v):
        try:
            return float(v)
        except (TypeError, ValueError):
            return None

    return (
        "ACLED",
        ev["event_id_cnty"],
        ev["event_date"],
        ev.get("event_type"),
        ev.get("sub_event_type"),
        ev.get("actor1"),
        ev.get("actor2"),
        ev.get("country"),
        ev.get("admin1"),
        ev.get("location"),
        num(ev.get("latitude")),
        num(ev.get("longitude")),
        int(ev.get("fatalities") or 0),
        ev.get("notes"),
    )


def main():
    load_dotenv()

    parser = argparse.ArgumentParser(description="Ingest ACLED events into Postgres")
    parser.add_argument("--countries", required=True,
                        help="Comma-separated, e.g. 'Georgia,Armenia,Azerbaijan'")
    parser.add_argument("--days", type=int, default=90,
                        help="How many days back from today (default 90)")
    args = parser.parse_args()

    email = os.environ.get("ACLED_EMAIL")
    password = os.environ.get("ACLED_PASSWORD")
    if not email or not password:
        sys.exit("Set ACLED_EMAIL and ACLED_PASSWORD in .env (see .env.example)")

    countries = [c.strip() for c in args.countries.split(",") if c.strip()]
    end = date.today()
    start = end - timedelta(days=args.days)

    print(f"Fetching ACLED events for {countries}, {start} .. {end}")
    token = get_token(email, password)

    conn = psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=os.environ.get("PGPORT", "5432"),
        dbname=os.environ.get("POSTGRES_DB", "pi_platform"),
        user=os.environ.get("POSTGRES_USER", "pi_analyst"),
        password=os.environ.get("POSTGRES_PASSWORD", "changeme"),
    )
    total = 0
    try:
        with conn, conn.cursor() as cur:
            for page_rows in fetch_pages(token, countries, start, end):
                values = [to_row(ev) for ev in page_rows]
                psycopg2.extras.execute_values(cur, UPSERT_SQL, values, page_size=1000)
                total += len(values)
    finally:
        conn.close()

    print(f"Done. {total} events upserted into events (source=ACLED).")


if __name__ == "__main__":
    main()
