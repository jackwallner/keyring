#!/usr/bin/env python3
"""Check every outside link the app opens.

Collects literal https URLs from the Swift sources, every subreddit in the
clubs catalog, and sample URLs from the builders that fill in a vehicle
(value guides, Amazon, NHTSA). Prints anything that is not a 2xx.

Some sites answer scripts with 403 or 202 and load fine in a browser (bot
walls). Those are listed separately: open them in a real browser before
calling them broken.

Usage: scripts/check-links.py
"""

import concurrent.futures as cf
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
BOT_WALLED = ("edmunds.com", "ebay.", "jdpower.com", "www.nhtsa.gov", "controller.com",
              "productsafety.gov.au", "frva.com", "bimmerfest.com", "rangerforums.net",
              "allfordmustangs.com", "vehiclerecalls.gov.au")

# One filled-in example per URL builder in Shared/Utilities/Links.swift and
# NHTSAClient. Update these when a builder's path changes.
SAMPLES = [
    "https://www.kbb.com/ford/f-150/2018/?intent=trade-in-sell&mileage=42000",
    "https://www.edmunds.com/ford/f-150/2018/appraisal-value/",
    "https://www.edmunds.com/appraisal/",
    "https://www.ebay.com/sch/i.html?_nkw=2018%20Ford%20F-150&LH_Sold=1&LH_Complete=1",
    "https://www.controller.com/listings/search?keywords=Cessna%20172",
    "https://www.autotrader.ca/cars/?kwd=Ford%20F-150",
    "https://www.amazon.com/s?k=2018%20Ford%20F-150%20oil%20filter",
    "https://www.nhtsa.gov/recalls?nhtsaId=20V682000",
    "https://api.nhtsa.gov/recalls/recallsByVehicle?make=ford&model=f-150&modelYear=2018",
    "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/1FTEW1EP5JFA00000?format=json",
]


def collect() -> set[str]:
    urls: set[str] = set(SAMPLES)
    for path in list((ROOT / "Keyring").rglob("*.swift")) + list((ROOT / "Shared").rglob("*.swift")):
        text = path.read_text()
        for url in re.findall(r'https://[^"\\\s)]+', text):
            if "\\(" in text[text.find(url):text.find(url) + len(url) + 2]:
                continue
            urls.add(url)
        for name in re.findall(r'\.subreddit\("([^"]+)"', text):
            urls.add(f"https://www.reddit.com/r/{name}/")
    # Template prefixes ("https://www.kbb.com/" built up in code) are covered by SAMPLES.
    return {u for u in urls if not u.endswith(("/r/", "/sch/i.html", "/s", "api.php", "/vehicles/", "/DecodeVinValues/", "recallsByVehicle", "nhtsaId=", "/app/id"))
            and "icloud.com/share" not in u}


def check(url: str) -> tuple[str, str, str]:
    """One retry, since forums throw the odd 5xx."""
    first = fetch(url)
    return first if first[1].startswith("2") else fetch(url)


def fetch(url: str) -> tuple[str, str, str]:
    result = subprocess.run(
        ["curl", "-sS", "-L", "--max-time", "25", "-A", UA, "-H", "Accept-Language: en-US",
         "-o", "/dev/null", "-w", "%{http_code} %{url_effective}", url],
        capture_output=True, text=True)
    code, _, final = (result.stdout or "000 ").partition(" ")
    return url, code, final


def main() -> int:
    urls = sorted(collect())
    with cf.ThreadPoolExecutor(16) as pool:
        results = list(pool.map(check, urls))
    broken, walled = [], []
    for url, code, final in results:
        if code.startswith("2") and code != "202":
            continue
        (walled if any(h in url for h in BOT_WALLED) else broken).append((code, url, final))
    print(f"{len(urls)} links checked")
    for title, rows in (("Broken", broken), ("Bot walled, check in a browser", walled)):
        if rows:
            print(f"\n{title}:")
            for code, url, final in rows:
                print(f"  {code} {url}" + (f" -> {final}" if final and final != url else ""))
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
