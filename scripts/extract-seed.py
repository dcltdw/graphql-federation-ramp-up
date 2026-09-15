#!/usr/bin/env python3
"""Extract seed fixtures from the kotlin-ramp-up Contentful export.

Run from the repo root:  python3 scripts/extract-seed.py
Reads ~/Github/kotlin-ramp-up/contentful/seed.json; writes the three JSON
resources the subgraphs load. Product identity is the SKU.
"""
import json
from pathlib import Path

SRC = Path.home() / "Github/kotlin-ramp-up/contentful/seed.json"
CATALOG = Path("catalog/src/main/resources/seed")
PERSONALIZATION = Path("personalization/src/main/resources/seed")


def v(field):
    return field.get("en-US") if isinstance(field, dict) else field


seed = json.loads(SRC.read_text())


def of_type(t):
    return [e for e in seed["entries"] if e["sys"]["contentType"]["sys"]["id"] == t]


categories = [{"key": v(e["fields"]["key"]), "name": v(e["fields"]["name"])} for e in of_type("category")]
category_key = {e["sys"]["id"]: v(e["fields"]["key"]) for e in of_type("category")}

products = []
for e in of_type("product"):
    f = e["fields"]
    products.append({
        "id": v(f["sku"]),
        "name": v(f["name"]),
        "priceMinor": v(f["priceMinor"]),
        "currency": v(f["currency"]),
        "category": category_key[v(f["category"])["sys"]["id"]],
        "tags": v(f.get("tags")) or [],
        "regions": v(f.get("regions")) or [],
    })
products.sort(key=lambda p: p["id"])

variants = {e["sys"]["id"]: e for e in of_type("ctaVariant")}
ctas = []
for e in of_type("cta"):
    f = e["fields"]
    ctas.append({
        "ctaId": v(f["ctaId"]),
        "name": v(f["name"]),
        "variants": [
            {"variantKey": v(variants[l["sys"]["id"]]["fields"]["variantKey"]),
             "headline": v(variants[l["sys"]["id"]]["fields"]["headline"])}
            for l in v(f["variants"])
        ],
    })
segments = sorted(v(e["fields"]["segmentId"]) for e in of_type("segment"))

CATALOG.mkdir(parents=True, exist_ok=True)
PERSONALIZATION.mkdir(parents=True, exist_ok=True)
(CATALOG / "products.json").write_text(json.dumps(products, indent=2) + "\n")
(CATALOG / "categories.json").write_text(json.dumps(categories, indent=2) + "\n")
(PERSONALIZATION / "ctas.json").write_text(json.dumps({"segments": segments, "ctas": ctas}, indent=2) + "\n")
print(f"{len(products)} products, {len(categories)} categories, {len(ctas)} ctas, {len(segments)} segments")
