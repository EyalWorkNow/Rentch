#!/usr/bin/env python3
import csv
import json
import sys
from pathlib import Path


FEATURES = {
    "parking": ("parking", "חניה"),
    "safe_room": ("mamad", "ממ\"ד"),
    "air_conditioning": ("airConditioning", "מזגן"),
    "renovated": ("renovated", "משופצת"),
    "bars": ("bars", "סורגים"),
    "for_roommates": ("roommates", "מתאימה לשותפים"),
    "bomb_shelter": ("bombShelter", "מקלט"),
    "elevator": ("elevator", "מעלית"),
    "balcony": ("balcony", "מרפסת"),
    "storeroom": ("storage", "מחסן"),
    "handicapped_access": ("accessible", "נגישות לנכים"),
    "furnished": ("furnished", "מרוהטת"),
    "pets_allowed": ("petsAllowed", "חיות מחמד מותר"),
    "floor_level_shelter": ("safeFloorSpace", "מרחב מוגן קומתי"),
}

CANONICAL_FEATURES = {
    "balcony": "מרפסת",
    "parking": "חניה",
    "storage": "מחסן",
    "airConditioning": "מזגן",
    "mamad": "ממ\"ד",
    "sunBalcony": "מרפסת שמש",
    "garden": "גינה",
    "elevator": "מעלית",
    "furnished": "ריהוט",
    "internetIncluded": "אינטרנט כלול",
    "equippedKitchen": "מטבח מאובזר",
    "petsAllowed": "חיות מחמד מותר",
    "laundryIncluded": "כביסה כלולה",
    "security": "שומר/אבטחה",
    "accessible": "נגישות לנכים",
    "sharedRoof": "גג משותף",
    "pool": "בריכה",
    "gym": "חדר כושר",
    "bars": "סורגים",
    "renovated": "משופצת",
    "roommates": "מתאימה לשותפים",
    "bombShelter": "מקלט",
    "safeFloorSpace": "מרחב מוגן קומתי",
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


def normalize_entry_date(value):
    value = (value or "").strip()
    if not value:
        return ""
    return value.split(" ")[0]


def normalize_created_at(row):
    for key in ("created_at", "createdAt", "posted_at", "published_at"):
        value = (row.get(key) or "").strip()
        if value:
            return value
    return None


def build_feature_payload(row):
    feature_flags = {key: False for key in CANONICAL_FEATURES}
    feature_labels = []
    for csv_key, (flag_key, label) in FEATURES.items():
        if not parse_bool(row.get(csv_key)):
            continue
        feature_flags[flag_key] = True
        if label not in feature_labels:
            feature_labels.append(label)
    return feature_flags, feature_labels


def convert_row(row):
    price = parse_int(row.get("price"), default=0)
    if price <= 0:
        return None

    feature_flags, feature_labels = build_feature_payload(row)
    street_number = parse_int(row.get("street_number"), default=-1)
    images = parse_images(row.get("image_urls"))
    entry_date = normalize_entry_date(row.get("entry_date"))
    transaction_type = normalize_transaction_type(row.get("transaction_type"))
    created_at = normalize_created_at(row)
    price_history = (
        [
            {
                "date": entry_date,
                "price": price,
                "transactionType": transaction_type,
            }
        ]
        if entry_date
        else []
    )
    return {
        "id": row["id"].strip(),
        "sourceUrl": row.get("url", "").strip(),
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
        "createdAt": created_at,
        "condition": (row.get("condition") or "").strip(),
        "ownerName": (row.get("contact_name") or "בעל הנכס").strip(),
        "agencyListing": parse_bool(row.get("agency_listing")),
        "features": feature_flags,
        "featureLabels": feature_labels,
        "media": [
            {"url": image_url, "type": "image"}
            for image_url in images
        ],
        "imageUrls": images,
        "transactionType": transaction_type,
        "model3d": {
            "viewerUrl": "",
            "glbUrl": "",
            "objUrl": "",
            "textureFolder": "",
            "floorPlanUrl": "",
            "modelQualityScore": None,
            "scanDate": None,
        },
        "legal": {
            "thirdPartyTransferAllowed": False,
            "commercialSaleAllowed": False,
            "aiTrainingAllowed": False,
            "consentVersion": "",
            "consentTimestamp": None,
            "consentSource": "external_import",
        },
        "priceHistory": price_history,
        "marketSignals": {
            "views": 0,
            "likes": 0,
            "saves": 0,
            "skips": 0,
            "contactRequests": 0,
            "avgTimeIn3dSeconds": 0,
            "liveViewers": 0,
            "likesToday": 0,
            "likesTodayDate": "",
            "detailViews": 0,
            "gallerySwipes": 0,
            "avgDetailStaySeconds": 0,
            "lastViewedAt": None,
        },
        "verification": {
            "verified": False,
            "method": "",
            "videoUrl": "",
            "capturedAt": None,
        },
        "verifiedListing": False,
        "verificationMethod": "",
        "verificationVideoUrl": "",
        "verifiedAt": None,
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
