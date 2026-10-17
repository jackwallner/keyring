#!/usr/bin/env python3
"""Make Keyring a free download in every territory.

A new app record has no price schedule and no availability, and App Review
refuses a submission without both. Safe to rerun: each half skips when it is
already set.

    ./scripts/asc-pricing-availability.py
"""

import asc_lib as A

APP_ID = "6823808045"

# The v2 availability endpoints live beside v1, so address both from the root.
A.API = "https://api.appstoreconnect.apple.com"


def ensure_free_pricing(client: A.ASCClient) -> None:
    try:
        manual = A.list_all(client, f"/v1/appPriceSchedules/{APP_ID}/manualPrices")
    except RuntimeError as error:
        if "404" not in str(error):
            raise
        manual = []
    if manual:
        print("price: already set")
        return

    points = A.list_all(client, f"/v1/apps/{APP_ID}/appPricePoints?filter[territory]=USA&limit=200")
    free = next((p for p in points if float(p["attributes"].get("customerPrice", -1)) == 0.0), None)
    if free is None:
        raise SystemExit("error: no free USA app price point")

    client.post(
        "/v1/appPriceSchedules",
        {
            "data": {
                "type": "appPriceSchedules",
                "relationships": {
                    "app": {"data": {"type": "apps", "id": APP_ID}},
                    "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                    "manualPrices": {"data": [{"type": "appPrices", "id": "${price0}"}]},
                },
            },
            "included": [
                {
                    "type": "appPrices",
                    "id": "${price0}",
                    "attributes": {"startDate": None},
                    "relationships": {
                        "appPricePoint": {"data": {"type": "appPricePoints", "id": free["id"]}}
                    },
                }
            ],
        },
    )
    print("price: set to free")


def ensure_availability(client: A.ASCClient) -> None:
    try:
        existing = client.get(f"/v1/apps/{APP_ID}/appAvailabilityV2").get("data")
    except RuntimeError as error:
        if "404" not in str(error):
            raise
        existing = None
    if existing:
        print("availability: already set")
        return

    territories = [t["id"] for t in A.list_all(client, "/v1/territories?limit=200")]
    rows = [
        {
            "type": "territoryAvailabilities",
            "id": f"${{t{i}}}",
            "attributes": {"available": True},
            "relationships": {"territory": {"data": {"type": "territories", "id": code}}},
        }
        for i, code in enumerate(territories)
    ]
    client.post(
        "/v2/appAvailabilities",
        {
            "data": {
                "type": "appAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "app": {"data": {"type": "apps", "id": APP_ID}},
                    "territoryAvailabilities": {
                        "data": [{"type": r["type"], "id": r["id"]} for r in rows]
                    },
                },
            },
            "included": rows,
        },
    )
    print(f"availability: {len(territories)} territories, new territories on")


def main() -> None:
    client = A.ASCClient.from_credentials()
    ensure_free_pricing(client)
    ensure_availability(client)


if __name__ == "__main__":
    main()
