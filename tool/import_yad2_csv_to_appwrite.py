#!/usr/bin/env python3
import argparse
import csv
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


FEATURES = {
    "parking": "חניה",
    "safe_room": "ממ\"ד",
    "air_conditioning": "מזגן",
    "renovated": "משופצת",
    "bars": "סורגים",
    "for_roommates": "מתאימה לשותפים",
    "bomb_shelter": "מקלט",
    "elevator": "מעלית",
    "balcony": "מרפסת",
    "storeroom": "מחסן",
    "handicapped_access": "גישה לנכים",
    "furnished": "מרוהטת",
    "pets_allowed": "חיות מחמד",
    "floor_level_shelter": "מרחב מוגן קומתי",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Import a Yad2 CSV into an Appwrite TablesDB table."
    )
    parser.add_argument("csv_path", type=Path, help="Source CSV file")
    parser.add_argument(
        "--endpoint",
        default="https://fra.cloud.appwrite.io/v1",
        help="Appwrite endpoint",
    )
    parser.add_argument(
        "--project-id",
        required=True,
        help="Appwrite project ID",
    )
    parser.add_argument(
        "--api-key",
        required=True,
        help="Server API key with tables.write scope",
    )
    parser.add_argument(
        "--database-id",
        required=True,
        help="Appwrite database ID",
    )
    parser.add_argument(
        "--table-id",
        default="properties",
        help="Target Appwrite table ID",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Import at most N valid rows, 0 means all",
    )
    parser.add_argument(
        "--offset",
        type=int,
        default=0,
        help="Skip the first N valid rows before importing",
    )
    parser.add_argument(
        "--sleep-ms",
        type=int,
        default=40,
        help="Delay between row writes in milliseconds",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse and validate without writing rows",
    )
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip rows that already exist in Appwrite",
    )
    return parser.parse_args()


def parse_int(value: str | None, default: int = 0) -> int:
    value = (value or "").strip()
    if not value:
        return default
    try:
        return int(float(value.replace(",", "")))
    except ValueError:
        return default


def parse_float(value: str | None, default: float = 0.0) -> float:
    value = (value or "").strip()
    if not value:
        return default
    try:
        return float(value.replace(",", ""))
    except ValueError:
        return default


def parse_bool(value: str | None) -> bool:
    return (value or "").strip() in {"1", "true", "True", "כן"}


def parse_images(value: str | None) -> list[str]:
    value = (value or "").strip()
    if not value:
        return []
    try:
        decoded = json.loads(value)
    except json.JSONDecodeError:
        return []
    if not isinstance(decoded, list):
        return []
    return [item for item in decoded if isinstance(item, str) and item.strip()]


def parse_transaction_type(value: str | None) -> str:
    return "sale" if (value or "").strip().lower() == "sale" else "rent"


def convert_row(row: dict[str, str]) -> dict[str, object] | None:
    price = parse_int(row.get("price"), default=0)
    if price <= 0:
        return None

    features = [
        label for key, label in FEATURES.items() if parse_bool(row.get(key))
    ]
    media = [
        {"url": image_url, "type": "image"}
        for image_url in parse_images(row.get("image_urls"))
    ]

    return {
        "propertyId": row["id"].strip(),
        "ownerUserId": "seed-yad2-import",
        "price": price,
        "rooms": parse_float(row.get("rooms")),
        "sizeM2": parse_int(row.get("size_m2")),
        "floor": (row.get("floor") or "").strip(),
        "totalFloors": (row.get("total_floors") or "").strip(),
        "city": (row.get("city") or "").strip(),
        "neighborhood": (row.get("neighborhood") or "").strip(),
        "street": (row.get("street") or "").strip(),
        "streetNumber": parse_int(row.get("street_number"), default=-1),
        "lat": parse_float(row.get("lat")),
        "lon": parse_float(row.get("lon")),
        "propertyType": (row.get("property_type") or "דירה").strip(),
        "entryDate": (row.get("entry_date") or "").strip(),
        "condition": (row.get("condition") or "").strip(),
        "features": json.dumps(features, ensure_ascii=False),
        "media": json.dumps(media, ensure_ascii=False),
        "status": "active",
        "sourceUrl": (row.get("url") or "").strip(),
        "ownerName": (row.get("contact_name") or "בעל הנכס").strip(),
        "agencyListing": 1 if parse_bool(row.get("agency_listing")) else 0,
        "transactionType": parse_transaction_type(row.get("transaction_type")),
    }


def load_rows(
    csv_path: Path,
    limit: int,
    offset: int,
) -> tuple[list[dict[str, object]], int]:
    rows: list[dict[str, object]] = []
    skipped = 0
    seen_ids: set[str] = set()
    valid_seen = 0

    with csv_path.open(newline="", encoding="utf-8-sig") as handle:
        for raw_row in csv.DictReader(handle):
            converted = convert_row(raw_row)
            if converted is None:
                skipped += 1
                continue

            property_id = converted["propertyId"]
            if not isinstance(property_id, str) or property_id in seen_ids:
                skipped += 1
                continue

            seen_ids.add(property_id)
            valid_seen += 1

            if valid_seen <= offset:
                continue

            rows.append(converted)

            if limit > 0 and len(rows) >= limit:
                break

    return rows, skipped


def post_json(
    url: str,
    *,
    project_id: str,
    api_key: str,
    payload: dict[str, object],
) -> tuple[int, str]:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Appwrite-Project": project_id,
            "X-Appwrite-Key": api_key,
        },
    )
    try:
        with urllib.request.urlopen(request) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8")


def import_rows(
    rows: list[dict[str, object]],
    *,
    endpoint: str,
    project_id: str,
    api_key: str,
    database_id: str,
    table_id: str,
    sleep_ms: int,
    skip_existing: bool,
) -> int:
    url = (
        f"{endpoint.rstrip('/')}/tablesdb/{database_id}/tables/{table_id}/rows"
    )
    imported = 0

    for index, row in enumerate(rows, start=1):
        property_id = row["propertyId"]
        if not isinstance(property_id, str):
            print(f"[skip] invalid property id at row {index}", file=sys.stderr)
            continue

        payload = {
            "rowId": property_id,
            "data": row,
        }
        status_code, body = post_json(
            url,
            project_id=project_id,
            api_key=api_key,
            payload=payload,
        )
        if 200 <= status_code < 300:
            imported += 1
            if imported % 100 == 0 or imported == len(rows):
                print(f"imported {imported}/{len(rows)}")
        elif status_code == 409 and skip_existing:
            if index % 100 == 0 or index == len(rows):
                print(f"processed {index}/{len(rows)} (existing rows skipped)")
        else:
            print(
                f"failed row {property_id} with HTTP {status_code}: {body}",
                file=sys.stderr,
            )
            return 1

        if sleep_ms > 0:
            time.sleep(sleep_ms / 1000)

    return 0


def main() -> int:
    args = parse_args()
    if not args.csv_path.exists():
        print(f"CSV not found: {args.csv_path}", file=sys.stderr)
        return 2

    rows, skipped = load_rows(args.csv_path, args.limit, args.offset)
    print(f"parsed {len(rows)} valid rows")
    print(f"skipped {skipped} rows")

    sample_bytes = len(json.dumps(rows[:5], ensure_ascii=False).encode("utf-8"))
    print(f"sample payload bytes for first 5 rows: {sample_bytes}")

    if args.dry_run:
        return 0

    return import_rows(
        rows,
        endpoint=args.endpoint,
        project_id=args.project_id,
        api_key=args.api_key,
        database_id=args.database_id,
        table_id=args.table_id,
        sleep_ms=args.sleep_ms,
        skip_existing=args.skip_existing,
    )


if __name__ == "__main__":
    raise SystemExit(main())
