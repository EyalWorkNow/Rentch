#!/usr/bin/env python3
import csv
import json
import sys
from pathlib import Path


FEATURES = {
    "parking": "חניה",
    "safe_room": "ממ״ד",
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


def parse_int(value, default=0):
    value = (value or "").strip()
    if not value:
        return default
    try:
        return int(float(value.replace(",", "")))
    except ValueError:
        return default


def parse_float(value, default=0.0):
    value = (value or "").strip()
    if not value:
        return default
    try:
        return float(value.replace(",", ""))
    except ValueError:
        return default


def parse_bool(value):
    return (value or "").strip() in {"1", "true", "True", "כן"}


def parse_images(value):
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


def normalize_transaction_type(value):
    return "sale" if (value or "").strip().lower() == "sale" else "rent"


def convert_row(row):
    price = parse_int(row.get("price"), default=0)
    if price <= 0:
        return None

    features = [
        label for key, label in FEATURES.items() if parse_bool(row.get(key))
    ]
    street_number = parse_int(row.get("street_number"), default=-1)
    return {
        "id": row["id"].strip(),
        "url": row.get("url", "").strip(),
        "price": price,
        "rooms": parse_float(row.get("rooms")),
        "sizeM2": parse_int(row.get("size_m2")),
        "floor": (row.get("floor") or "").strip(),
        "totalFloors": (row.get("total_floors") or "").strip(),
        "city": (row.get("city") or "").strip(),
        "neighborhood": (row.get("neighborhood") or "").strip(),
        "street": (row.get("street") or "").strip(),
        "streetNumber": street_number,
        "lat": parse_float(row.get("lat")),
        "lon": parse_float(row.get("lon")),
        "propertyType": (row.get("property_type") or "דירה").strip(),
        "entryDate": (row.get("entry_date") or "").strip(),
        "condition": (row.get("condition") or "").strip(),
        "ownerName": (row.get("contact_name") or "בעל הנכס").strip(),
        "agencyListing": parse_bool(row.get("agency_listing")),
        "features": features,
        "imageUrls": parse_images(row.get("image_urls")),
        "transactionType": normalize_transaction_type(
            row.get("transaction_type")
        ),
    }


def main():
    if len(sys.argv) != 3:
        print(
            "usage: convert_yad2_csv_to_proxy_json.py <input.csv> <output.json>",
            file=sys.stderr,
        )
        return 2

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    listings = []
    skipped = 0
    seen_ids = set()
    with input_path.open(newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            item = convert_row(row)
            if item is None:
                skipped += 1
                continue
            if item["id"] in seen_ids:
                skipped += 1
                continue
            seen_ids.add(item["id"])
            listings.append(item)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(listings, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"wrote {len(listings)} listings to {output_path}")
    print(f"skipped {skipped} rows")


if __name__ == "__main__":
    raise SystemExit(main())
