# Family Vehicle Maintenance Log: Research Brief

Researched 2026-10-16. Reddit pages are blocked to direct fetch, so threads came from the pullpush.io Reddit archive. App Store numbers come from the iTunes Search/Lookup API and the customer-review RSS feeds (US storefront). Every API endpoint below was called live today with curl.

---

## 0. Bottom line

1. **CARFAX Car Care is the default.** It is free, has 128K ratings at 4.84, pulls in shop records automatically, and Reddit's top tip is to "punch in the VIN" of a used car before buying it. A free log alone won't win. The openings are the things CARFAX does badly: DIY records stay private, custom schedules are weak, logouts are frequent, and the app keeps upselling trade-ins.
2. **Losing data is the top complaint across the category.** Several apps have been abandoned or are rotting:
   - Fuelly: last update 2024-06, with login lockouts.
   - Simply Auto: last update 2022-03, and its Google Drive backup is broken.
   - Car Minder: gone.
   - Vehicle Maintenance Tracker: a 2026 update wiped service dates for its users.
   Durability (iCloud, no account, free export) is now table stakes. One indie app, SteerLog, already pitches exactly that.
3. **Family sharing is an unsolved, paid-for need.** People share one login, sync breaks, "multi-driver never worked", and Fuelly "does not automatically sync across devices or users." No iOS app does real per-person sharing without an account. CloudKit CKShare is the obvious technical answer.
4. **The resale record is the emotional payoff.** People keep binders for the next buyer. One owner lost money because he couldn't prove a timing belt was done. CARFAX doesn't show DIY entries on the public report. A shareable, verifiable "service passport" PDF or link fills that gap.
5. **People hate subscriptions and ads, and pay happily once.** Road Trip MPG costs $6.99 one-time and rates 4.90. Users still praise AUTOsist's $20 "forever" fee years later. Drivvo and Fuelio draw 1-star reviews for paywalling exports and adding ads.
6. **Distribution is the hard part.** Reddit is flooded with indie car-log launches (2025-26: HONK, SteerLog, OdoKeep, Pocket Car, Motored, AutoDex, MyAutoLog, Carmainty, RevFolio, VehIQ and more), and car subreddits are openly hostile to app promotion. People look for an app at specific moments: buying a used car, selling one, a warranty claim, or a mechanic asking for history.

---

## 1. Voice of customer (Reddit and forums)

### What people actually use today
- **Paper is still the default:** a binder, a folder in the glovebox, or notes in the owner's manual. Next come Google Sheets or Excel, then the Notes app, then CARFAX Car Care.
  - Threads: [r/askcarguys 1n382ho](https://reddit.com/r/askcarguys/comments/1n382ho/how_do_real_car_folks_keep_car_records_organized/), [r/Cartalk 1w6ouac](https://reddit.com/r/Cartalk/comments/1w6ouac/how_do_you_keep_your_cars_maintenance_and_repair/), [r/askcarguys 1t9o4qy](https://reddit.com/r/askcarguys/comments/1t9o4qy/how_do_you_guys_keep_track_of_your_car_maintenance/), [r/askcarguys 1wnfixy](https://reddit.com/r/askcarguys/comments/1wnfixy/how_do_you_actually_keep_track_of_everything/), [r/4Runner 15ymou0](https://reddit.com/r/4Runner/comments/15ymou0/how_do_you_guys_keep_track_of_maintenance/).
- **A common spreadsheet setup** is one Google Sheet with a tab per vehicle (date, mileage, service, cost, shop) and receipts kept in a folder.
- **Self-hosters use LubeLogger:** "love that the goal posts won't change" on their own data ([r/selfhosted](https://reddit.com/r/selfhosted/comments/1v7eegf/whats_an_incredibly_good_but_not_well_known_self/p0012rj/)).

### What they hate
| Pain | Evidence (short quotes) |
|---|---|
| Ads | "Drivvo is riddled with ads" ([r/Audi](https://reddit.com/r/Audi/comments/1sr0mwr/i_found_that_all_car_maintenance_trackers_on/pal09di/)). HONK launch title: "all car maintenance trackers on iPhone are shit, or shit AND riddled with ads" ([r/Audi](https://reddit.com/r/Audi/comments/1sr0mwr/i_found_that_all_car_maintenance_trackers_on/)) |
| Subscriptions | Fuelly "requires a shitty annual subscription" ([r/rav4club](https://reddit.com/r/rav4club/comments/1cxk3te/22_rav4_hybrid_tells_me_im_getting_436_mpg_for_my/l55rge5/)). "Ugh, I freakin' HATE subscription apps!" about a car log ([r/apple](https://reddit.com/r/apple/comments/aveqka/apple_beginning_new_push_for_subscriptionbased/ehgkyx1/)) |
| Data loss and abandonment | "My car maintenance app data was lost after the dev stopped updating" ([r/bicycling](https://reddit.com/r/bicycling/comments/1nt2nml/do_any_other_chain_waxers_track_their_chains_did/ngqmdmn/)). An old app "is no longer made... can't find anything that's even close" ([r/applehelp](https://reddit.com/r/applehelp/comments/1ovul7b/been_rocking_an_iphone_13_mini_for_4_years_should/noo45bs/)) |
| Multi-user sharing is flaky | Simply Auto: "multindriver configuration never worked right for me" ([r/askcarguys](https://reddit.com/r/askcarguys/comments/1wnfixy/how_do_you_actually_keep_track_of_everything/pbffsuv/)). AUTOsist workaround: "My wife uses same login" ([r/ToyotaSienna](https://reddit.com/r/ToyotaSienna/comments/1pylk63/diy_maintenance_void_warranty/nyietbl/)) |
| CARFAX limits | DIY entries "disappear when you remove the vehicle" ([r/Ford](https://reddit.com/r/Ford/comments/1wtcf1b/what_did_your_last_the_works_oil_change_cost_you/pcurm7q/)). "the stuff you add only shows for yourself" ([r/askcarguys](https://reddit.com/r/askcarguys/comments/1t9o4qy/how_do_you_guys_keep_track_of_your_car_maintenance/ol4d4c3/)). "Can't add specific items or define a schedule" ([r/askcarguys](https://reddit.com/r/askcarguys/comments/1t9o4qy/how_do_you_guys_keep_track_of_your_car_maintenance/ol4zs3z/)) |
| Spreadsheets on a phone | "Spreadsheets aren't really designed to be viewed on phone" ([r/Audi](https://reddit.com/r/Audi/comments/1sr0mwr/i_found_that_all_car_maintenance_trackers_on/ohc03ij/)) |
| Faded thermal receipts | "My thermal paper reciepts are all faded to blank" ([r/askcarguys](https://reddit.com/r/askcarguys/comments/1n382ho/how_do_real_car_folks_keep_car_records_organized/nbuf37x/)) |
| Receipts spread across places | Photos in the camera roll, to-dos in Notes, invoices in email ([r/askcarguys ol4o3qz](https://reddit.com/r/askcarguys/comments/1t9o4qy/how_do_you_guys_keep_track_of_your_car_maintenance/ol4o3qz/)) |

### What they want
- **Proof for resale and warranty claims.**
  - "When it comes time to sell, the binder is worth it's weight in gold" ([r/askcarguys](https://reddit.com/r/askcarguys/comments/1n382ho/how_do_real_car_folks_keep_car_records_organized/nbdv4nz/)).
  - A buyer asked about the timing belt and "knocked the price down over it" ([r/Cartalk](https://reddit.com/r/Cartalk/comments/1w6ouac/how_do_you_keep_your_cars_maintenance_and_repair/p8lo0mq/)).
  - Warranty: a dealer said "NO WARRANTY WORK WITHOUT A PAPER TRAIL" and the owner's records got him a new engine ([r/Cartalk](https://reddit.com/r/Cartalk/comments/1w6ouac/how_do_you_keep_your_cars_maintenance_and_repair/p7ozy2d/)).
- **Export and portability.** The HONK dev's spec was "Export everything if I'm selling the vehicle." Drivvo users import their CSVs into newer apps ([r/carros](https://reddit.com/r/carros/comments/1wu849d/fiz_um_app_pra_saber_quanto_meu_carro_me_custa/pd22o3y/)).
- **Reminders by miles OR months.** Users like Autozis-style "each 10000 miles or each 12 months" ([r/ToyotaEcho](https://reddit.com/r/ToyotaEcho/comments/1p7m1ay/need_general_advice_about_maintenance_for_low/nr0z7xi/)).
- **Household fleets beyond cars.**
  - "I take care of my EUV and two ICE vehicles" ([r/BoltEV](https://reddit.com/r/BoltEV/comments/1khf8xm/any_recommendations_for_a_good_app_that_keeps/mrmazua/)).
  - "between me the wife and kids we have 5 cars" ([r/motorcycles](https://reddit.com/r/motorcycles/comments/1jcskak/how_do_you_folks_keep_track_of_maintenance_or_do/mi5itrk/)).
  - An AUTOsist reviewer tracks a generator, an RV, 3 motorcycles and a truck, and hit the 5-vehicle cap.
- **Spouse in the loop.** Road Trip MPG user: "log each fill up with my wife and her car too" ([r/SubaruForester](https://reddit.com/r/SubaruForester/comments/1rfuno0/2021_forester_premium_mileage_question/o7w41qk/)). A LubeLogger user set up SSO so "my family" can use it ([r/Audi](https://reddit.com/r/Audi/comments/1sr0mwr/i_found_that_all_car_maintenance_trackers_on/ohcue0b/)).
- **A surprising nuance: cost privacy inside the household.** "do not want wifey to see the dollar number" ([r/askcarguys](https://reddit.com/r/askcarguys/comments/1wnfixy/how_do_you_actually_keep_track_of_everything/pbk3bol/)). Several others say they deliberately don't total costs. A "hide costs" option per person or per vehicle is cheap to build and on-brand.
- **Fuel tracking is a split audience.** Fuelly users are data nerds (one logged 298k miles and 1,047 fill-ups in [r/JeepPatriot](https://reddit.com/r/JeepPatriot/comments/1wvb8p6/what_is_the_average_of_your_jeep/pdbburx/)). Many maintenance-only users find it "Boring as fuck." Make fuel optional, not the core.
- **VIN.** People mostly use the CARFAX VIN trick for used-car history. In-app, the VIN is reference data: owners copy-paste it, and a CARFAX review complains when the VIN is masked.

### Warnings from the threads
- Reminders alone don't change behavior: "Those who don't will just snooze reminders" ([r/MechanicAdvice](https://reddit.com/r/MechanicAdvice/comments/1wcaqsb/how_do_you_recommend_car_owners_keep_track_of/p8wjfd1/)).
- Riders are hostile to auto ride/GPS tracking ("solution in search of a problem", [r/motorcycles](https://reddit.com/r/motorcycles/comments/1poau0m/how_do_you_track_your_bikes_rides_fuel_and/nudxa8i/)).
- Car subs punish self-promotion. On [r/Autos](https://reddit.com/r/Autos/comments/1tmg81t/i_wanted_one_place_to_see_my_cars_entire_service/onmjric/) the top reply (score 24) tells a dev to stop spamming his app.
- Demand is moment-driven. "nobody is really searching for car maintenance app until they already have the problem" ([r/SaaS](https://reddit.com/r/SaaS/comments/1w70rjd/i_underestimated_how_much_harder_distribution_is/p7wwscl/)).
- EV owners need little: "There's no service needed" ([r/BoltEV](https://reddit.com/r/BoltEV/comments/1khf8xm/any_recommendations_for_a_good_app_that_keeps/mr95n90/)). EVs belong in a mixed garage, not as the target market.

---

## 2. iOS competitors (US App Store, 2026-10-16)

| App | Ratings | Model and price | Sharing | Export/PDF | Schedules | Last update | Standout complaints |
|---|---|---|---|---|---|---|---|
| CARFAX Car Care | 127,965 at 4.84 | Free (lead-gen for CARFAX, shops, trade-ins) | Multi-vehicle garage; no real sharing | No export | Yes, recommended by VIN; recalls; value estimate | 2026-10 | 2026 forced logouts; "more concerned about trying to get trade-in values"; wiped history; masked VIN; says you missed oil changes you didn't |
| Jerry | 30,819 at 4.69 | Free, funded by insurance brokerage | No | No | Reminders and recalls | 2026-09 | Insurance-quote complaints dominate; maintenance is a side feature |
| Fuelly | 29,618 at 4.74 | Free with ads; Premium $0.99/mo or $7.99/yr | One account across 2 phones, buggy | CSV email | Reminders, no OEM data | **2024-06-03 (stale)** | Login lockouts lose years of data; "does not automatically sync across devices or users" |
| Vehicle Maintenance Tracker (Hai Nguyen) | 2,934 at 4.30 | Free plus a Pro subscription | No | CSV | Manual due dates | 2026-06 | **2026 update reset service dates to 0001/1900** for many users |
| My Car (KineApps) | 1,172 at 4.70 | Free (3 vehicles); Premium $1.49/mo or $10.99/yr; business tiers | Driver sharing (Premium) | PDF reports (Premium); imports Fuelly, Drivvo, Fuelio | Smart reminders (Premium) | 2026-09 | Paywall after one custom reminder; sync and premium-unlock failures |
| Drivvo | 973 at 4.69 (much bigger on Android) | Free with heavy ads; Pro $5.99 to $49.90/yr; Fleet up to $119.99 | Multi-driver (each sees only their own entries) | CSV/Excel is Pro-only ($25+/yr) | Date/mile reminders | 2026-10 | "multiple ads on launch"; export paywall; tiny font |
| Simply Auto | 867 at 4.10 | Gold $9.99 one-time, Platinum $9.99/yr or $29.99 lifetime | Multi-driver (Platinum) | CSV, reports | Reminders | **2022-03-24 (abandoned)** | Google Drive backup broken since 2025; paid users get ads; no support |
| CarScope (CarIQ) | 658 at 4.50 | Subscription | No | Weak CSV import | Reminders | 2026-09 | Data loss on sync; 8 notifications in 2 minutes |
| Road Trip MPG | 628 at **4.90** | **$6.99 one-time**, no IAP | iCloud or Dropbox sync; **Family Sharing (6)** | CSV and Dropbox backups | Service reminders | 2026-09 | Clunky date entry; fuel-first. Loved for 15 years by its users |
| Car Cave | 373 at 4.67 | Free plus ~$1 unlock | No | **No export** | Intervals tied (1k mi = 1 mo) | 2026-10 | "Closest replacement to Car Minder" |
| AUTOsist | 345 at 4.22 | Plus $9.99, Pro $19.99, Gold $49.99; fleet $99.99+ | Users and permissions (fleet) | Excel and PDF | Factory PM schedules added | 2026-08 | 5-vehicle cap for personal use; slow; account loss |
| Fuelio (Sygic) | 164 at 4.54 | iOS needs Pro (Android is free) | No | Sheets on Android | Basic | 2026-10 | iOS feature parity anger |
| FIXD | 25,852 at 4.61 | OBD dongle plus subscription | Family plan | No | Mileage-based | 2026-10 | Different category (hardware) |

Not on the US store or dead: **Car Minder** (abandoned; Car Cave users came from it), **Hum** (Verizon; only "HUM Driver/Rideshare" apps remain, 67 ratings), **Openbay** (no consumer app found), **Torque** (Android OBD only), **Revv** (an Indian rental app, not maintenance), **myCARFAX** (merged into CARFAX Car Care). **Vehicle Smart** and **Total Car Check** are UK MOT-check apps.

Implications:
- The paid indie tier is small (hundreds to low thousands of ratings), and the incumbents are stale.
- No app combines account-free family sharing, real durability, and a resale-grade report.
- The ratings ceiling sits with ad-supported giants, so ASO for "car maintenance" means fighting CARFAX (128K ratings). Long-tail terms like "maintenance log", "service record", "oil change reminder" and "vehicle log" are the realistic targets. Run Astro popularity checks before committing.

---

## 3. Free data sources (verified live 2026-10-16)

| Source | Endpoint (working) | Notes |
|---|---|---|
| NHTSA vPIC VIN decode | `https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/{VIN}?format=json` (optional `&modelyear=`) | Flat JSON: Make, Model, ModelYear, Trim, BodyClass, FuelTypePrimary, ElectrificationLevel (BEV/HEV/PHEV), DisplacementL, EngineCylinders, DriveType, VehicleType. Returns data plus an `ErrorText` on a bad check digit. Batch: `DecodeVINValuesBatch` (POST). Free, no key. |
| vPIC makes by type | `.../GetMakesForVehicleType/motorcycle?format=json` | 1,694 motorcycle makes. Also `car`, `truck`, `multipurpose passenger vehicle (mpv)`, `trailer`. |
| vPIC models | `.../GetModelsForMakeYear/make/honda/modelyear/2020?format=json` | 81 models; append `/vehicletype/motorcycle` for bikes (69). |
| NHTSA recalls | `https://api.nhtsa.gov/recalls/recallsByVehicle?make=honda&model=accord&modelYear=2018` | Fields: NHTSACampaignNumber, Component, Summary, Consequence, Remedy, **parkIt, parkOutSide, overTheAirUpdate**. Also `/recalls/campaignNumber?campaignNumber=`. Searches by year/make/model, **not VIN**. VIN-level open-recall status is the web tool at nhtsa.gov/recalls; I found no free public API for it. Use "may apply, check your VIN" copy plus a deep link. |
| NHTSA complaints | `https://api.nhtsa.gov/complaints/complaintsByVehicle?make=&model=&modelYear=` | 1,891 for a 2018 Accord. Good for "known issues" by component. |
| NHTSA safety ratings | `https://api.nhtsa.gov/SafetyRatings/modelyear/2018/make/honda/model/accord` | Returns a VehicleId, then the star ratings. |
| FuelEconomy.gov | `https://www.fueleconomy.gov/ws/rest/vehicle/menu/options?year=2020&make=Honda&model=Accord`, then `/ws/rest/vehicle/{id}` | Send `Accept: application/json`. Gives city08/highway08/comb08, fuelType, atvType (EV/Hybrid/Plug-in), VClass. US light-duty only (no motorcycles or RVs). Use it as an "EPA rated vs your real MPG" benchmark. |
| CarQuery | `carqueryapi.com/api/0.3/` | Returned empty today. Treat it as unmaintained and don't depend on it. |
| Edmunds API | n/a | Non-partner keys were disabled 2018-02-15, and Edmunds is not accepting new applicants ([FAQ](https://developer.edmunds.com/faq.html)). |
| Kelley Blue Book | No public API | Values are B2B-licensed (InfoDriver; contact b2b.kbb.com). **The honest approach is a deep link.** Verified pattern: `https://www.kbb.com/{make}/{model}/{year}/{style-slug}/?intent=trade-in-sell&mileage=60000&condition=good&pricetype=trade-in&zipcode=98684`. The page state echoed mileage, condition, pricetype and zip. The style slug is KBB's own (e.g. `lx-sedan-4d`), so the safe default is the year page `https://www.kbb.com/{make}/{model}/{year}/`, where the user picks a style. Make and model slugs are lowercase and hyphenated. Undocumented, so test the links in CI. Never scrape or display KBB numbers in-app. |
| Amazon affiliate | Search: `https://www.amazon.com/s?k=5w-30+full+synthetic&tag=YOURTAG-20`. Item: `https://www.amazon.com/dp/{ASIN}?tag=YOURTAG-20` | Needs an Associates account; the account is reviewed after **3 qualifying sales in the first 180 days** ([help](https://affiliate-program.amazon.com/help/node/topic/G8TW5AE9XL2VX9VM)). The app must be an **Approved Mobile Application**. Never render Amazon in a WebView or in-app browser, so open Safari or the Amazon app. No link shorteners or cloaking. Required disclosure: "As an Amazon Associate I earn from qualifying purchases." **No Special Links in printed material**, so keep affiliate links out of the PDF passport. Show prices only via PA-API, with a timestamp ([policies](https://affiliate-program.amazon.com/help/operating/policies)). Apple allows links for physical goods. |

Paid options exist if needed later: MOTOR, DataOne, CarMD and Vehicle Databases sell OEM maintenance schedules and valuations. All are contract-priced.

---

## 4. Maintenance schedules

**No free source of manufacturer schedules exists.** vPIC, FuelEconomy.gov and NHTSA carry no service intervals. The commercial providers (MOTOR, DataOne, CarMD) need contracts. Competitors either skip it (the HONK dev called it "beyond the scope") or license it (AUTOsist "added the factory PM schedules"; CARFAX builds its schedule from VIN data).

**A defensible approach:**
1. Decode the VIN, which sets the powertrain from `FuelTypePrimary` and `ElectrificationLevel`.
2. Apply a generic template.
3. Label everything "typical interval, check your owner's manual," with every interval editable.
4. Support "miles OR months, whichever first."
5. Offer "follow my car's oil-life monitor" (Honda Maintenance Minder and similar) as a reminder type. Consumer Reports warns shops push intervals tighter than the manual, so conservative-but-editable is right.

| Item | ICE gas | Hybrid | Diesel | EV | Motorcycle |
|---|---|---|---|---|---|
| Engine oil and filter | Synthetic 5k-10k mi or 12 mo; conventional 3k-5k (KBB) | Same as ICE (often 10k/12 mo) | 7.5k-10k or per OLM | n/a | 3k-8k mi or yearly, per manual |
| Tire rotation | 5k-8k mi (KBB) | 5k-7.5k | 5k-7.5k | 6,250 mi / 10,000 km or 2/32" tread difference (Tesla) | n/a (check tread and age) |
| Engine air filter | 15k-30k mi (inspect at oil change) | 15k-30k | 15k-30k | n/a | 6k-12k or yearly |
| Cabin air filter | 15k-30k mi or yearly | Same | Same | Every 1-2 yrs (Tesla manual varies by region) | n/a |
| Brake fluid | 2-3 yrs (many OEMs) | 2-3 yrs | 2-3 yrs | Check every 4 yrs, replace as needed (Tesla) | 2 yrs |
| Brake pads | Inspect each oil change; typically 25k-50k (CR) | Last longer (regen) | Inspect | Last much longer; Tesla: clean and lube calipers yearly or 12.5k mi in salt areas | Inspect |
| Coolant | Long-life ~100k-150k first, then ~50k | Engine plus **inverter coolant** (e.g. Kia PHEV ~32k per owners, Toyota ~150k first) | ~100k+ | Battery coolant rarely (Tesla: not needed under normal use) | 2-3 yrs (liquid-cooled) |
| Spark plugs | Iridium ~100k (CR, KBB); copper ~30k | ~100k-120k | n/a (glow plugs as needed) | n/a | 8k-16k (varies widely) |
| Transmission/CVT fluid | 30k-60k severe, 60k-100k normal; "lifetime" is debated | e-CVT per manual | 30k-60k | Drive-unit fluid rarely | Gear oil per manual (shaft drive) |
| Timing belt (if equipped) | 60k-105k | Same | Same | n/a | n/a |
| 12V battery | Test at 3 yrs; replace 3-5 yrs (KBB 4-5) | Same | Same | 12V/LV battery ~3-5 yrs | 2-4 yrs |
| Wipers | 6-12 mo | Same | Same | Same | n/a |
| Diesel-specific | | | Fuel filter 15k-30k; DEF top-ups; DPF per manual | | |
| Moto-specific | | | | | Chain clean and lube every ~300-600 mi; valve clearance check per manual (e.g. 16k on a VFR) |
| Tire age | Replace at ~6-10 yrs regardless of tread | Same | Same | Same | ~5 yrs |
| RV / boat (engine hours) | Generator oil ~100-150 hrs; roof sealant inspection every 6-12 mo; trailer bearings yearly or ~12k mi | | | | Outboard service and gear oil every 100 hrs or yearly; water pump impeller every 1-3 yrs |

Sources: [KBB intervals](https://www.kbb.com/car-advice/car-maintenance-service-intervals/), Consumer Reports maintenance guides (paywalled excerpts: plugs ~100k, pads 25k-50k, synthetic only if the manual requires it), [Tesla Model Y intervals](https://www.tesla.com/ownersmanual/modely/en_sg/GUID-E95DAAD9-646E-4249-9930-B109ED7B1D91.html). The RV, boat and motorcycle rows are common-practice ranges: ship them as editable defaults, not claims. **Engine hours as a meter** (generators, boats, mowers, tractors) is a real gap. Users already bend car apps to track generators.

---

## 5. Clubs, forums, subreddits by make

Codes: [ok] means it returned HTTP 200 to curl today; [bot] means a Cloudflare 403/202, so the site exists but blocks bots. Subreddits are the well-known names, not individually re-fetched because Reddit blocks fetching.

| Make | National club / org | Forums | Subreddits |
|---|---|---|---|
| Toyota | Toyota Land Cruiser Assn tlca.org [ok] | toyotanation.com [bot], tacomaworld.com [ok], tundras.com [ok], toyota-4runner.org [bot], rav4world.com [bot], priuschat.com [ok], siennachat.com [bot], ft86club.com [ok], gr86.org [bot] | r/Toyota r/Tacoma r/4Runner r/ToyotaTundra r/rav4club r/prius r/GR86 |
| Lexus | none official in US | clublexus.com [ok] | r/Lexus |
| Ford | Mustang Club of America mustang.org (500 today); Shelby American Automobile Club saac.com [ok] | f150forum.com [ok], ford-trucks.com [ok], bronco6g.com [bot], macheforum.com [ok], rangerforums.net [ok], mustang6g.com [bot] | r/Ford r/f150 r/Mustang r/bronco r/FordMaverickTruck r/MachE |
| Chevrolet | NCRS ncrs.org [ok]; NCCC corvettesnccc.org [ok]; National Corvette Museum ncm.org [ok] | corvetteforum.com [ok], camaro6.com [ok], silveradosierra.com [bot], gm-trucks.com [bot], coloradofans.com [bot], chevybolt.org [bot] | r/Chevrolet r/Corvette r/camaro r/Silverado r/chevycolorado r/BoltEV |
| GMC | none | gmcforum.com [ok], silveradosierra.com [bot] | r/gmc |
| Honda | GWRRA gwrra.org [ok] (Gold Wing) | civicx.com [ok], driveaccord.net [bot], piloteers.org [bot], ridgelineownersclub.com [bot], s2ki.com [ok] | r/Honda r/civic r/accord r/crv r/hondaodyssey |
| Acura | none | acurazine.com [ok] | r/Acura |
| Nissan | Z Car Club of America zcca.org [ok] | nissanclub.com [bot], my350z.com [ok], zclub.net [ok], titantalk.com [bot], nissanfrontier.org [ok], rogueforums.com [ok] | r/Nissan r/370z r/nissanleaf |
| Infiniti | none | myg37.com [ok], g35driver.com [ok] | r/infiniti |
| Hyundai | none | hyundai-forums.com [bot], ioniqforum.com [bot], palisadeforum.com [bot], hyundaiperformance.com [bot] | r/Hyundai r/Ioniq5 |
| Kia | none | kia-forums.com [bot], kiatelluride.org [ok], kiaev6forum.com [ok] | r/kia r/KiaTelluride r/KiaEV6 |
| Genesis | none | genesisforums.org [bot] | r/GenesisMotors |
| Jeep | Jeep Jamboree USA jeepjamboreeusa.com [ok] | jeepforum.com [bot], wranglerforum.com [bot], jlwranglerforums.com [bot], cherokeeforum.com [ok], jeepgarage.org [bot] | r/Jeep r/JeepWrangler r/GrandCherokee |
| Ram | none | 5thgenrams.com [ok], ramforum.com [bot], cumminsforum.com [bot] | r/ramtrucks r/Cummins |
| Dodge | none | challengertalk.com [bot], chargerforums.com [bot] | r/Dodge r/Challenger |
| Chrysler | Chrysler 300 Club chrysler300club.com [ok] | pacificaforums.com [bot] | r/Chrysler |
| Subaru | **no national US club** | nasioc.com [bot], subaruoutback.org [bot], subaruforester.org [bot], wrxforums.com [bot] | r/subaru r/WRX r/Subaru_Outback r/SubaruForester |
| Mazda | **Miata Club of America is defunct (closed 2000)**; miata.net [bot] lists regional clubs | forum.miata.net [bot], mazda3revolution.com [bot], cx5forum.com [bot], cx50forums.com [bot], cx90forum.com [bot], mazdas247.com [ok] | r/mazda r/Miata r/CX5 |
| Tesla | Official Tesla Owners Clubs directory [engage.tesla.com/pages/clubs](https://engage.tesla.com/pages/clubs) | teslamotorsclub.com [bot] | r/teslamotors r/TeslaModel3 r/TeslaModelY |
| Volkswagen | VW Club of America vwclub.org [ok] | vwvortex.com [bot], golfmk8.com, atlasforums.com, idforums.com | r/Volkswagen r/GolfGTI |
| Audi | Audi Club North America audiclubna.org [ok] | audiworld.com [ok], audizine.com [bot] | r/Audi |
| BMW | BMW CCA bmwcca.org [ok]; BMW MOA bmwmoa.org [ok] (bikes) | bimmerpost.com [bot], bimmerfest.com [ok] | r/BMW r/e46 r/BMWMotorrad |
| Mercedes-Benz | MBCA mbca.org [bot] | mbworld.org [ok], benzworld.org [bot] | r/mercedes_benz |
| Porsche | Porsche Club of America pca.org [ok] | rennlist.com [ok], 6speedonline.com [ok], planet9.com | r/Porsche |
| Volvo | Volvo Club of America vcoa.org [ok] | swedespeed.com [bot], volvoforums.com | r/Volvo |
| Cadillac | Cadillac & LaSalle Club cadillaclasalleclub.org [ok] | cadillacforums.com [bot] | r/Cadillac |
| Buick | Buick Club of America buickclub.org [ok] | n/a | r/Buick |
| Lincoln | Lincoln & Continental Owners Club lincolnclub.org [ok] | lincolnforum.com [ok] | r/lincoln |
| Mitsubishi | none | evolutionm.net [ok] | r/mitsubishi |
| Land Rover | none | rangerovers.net [bot], landroverforums.com | r/landrover r/RangeRover |
| Jaguar | Jaguar Clubs of North America jcna.com [ok] | jaguarforums.com | r/Jaguar |
| MINI | n/a | northamericanmotoring.com [ok], motoringmini.com [ok] | r/MINI |
| Alfa Romeo | Alfa Romeo Owners Club aroc-usa.org [ok] | alfabb.com [bot], alfaromeoforum.com | r/alfaromeo |
| Fiat | none | fiat500usaforum.com [bot] | r/fiat |
| Rivian | none | rivianforums.com [ok], rivianownersforum.com [bot] | r/Rivian |
| Lucid | none | lucidowners.com [ok] | r/LUCID |
| Polestar | none | polestar-forum.com [bot] | r/Polestar |
| Maserati | none | maseratilife.com [bot] | r/maserati |
| Ferrari | Ferrari Club of America ferrariclubofamerica.org [bot] | ferrarichat.com [bot] | r/ferrari |
| Lamborghini | none | lamborghini-talk.com [bot] | r/lamborghini |
| Saab / AMC (classic) | Saab Club of NA saabclub.com [ok]; AMC Rambler Club amcrc.com [ok] | n/a | r/saab |
| Harley-Davidson | H.O.G. harley-davidson.com/us/en/content/hog.html [ok] | hdforums.com [ok] | r/harley |
| Other motorcycles | AMA americanmotorcyclist.com [ok]; GWRRA; BMW MOA | advrider.com [bot], ducatimonster.org [bot], triumphrat.net [bot] | r/motorcycles r/Ducati r/Triumph r/GoldWing |
| RVs | FRVA (formerly FMCA; fmca.com redirects to frva.com) [bot]; Escapees escapees.com [ok]; Good Sam goodsam.com [ok] | irv2.com [bot] | r/RVLiving r/GoRVing |
| Boats | BoatUS boatus.com [ok] | thehulltruth.com [bot], cruisersforum.com [bot] | r/boating r/sailing |
| Cross-marque | AACA aaca.org [ok]; SCCA scca.com [ok]; NASA drivenasa.com [bot] | | r/Cartalk r/MechanicAdvice r/projectcar r/askcarguys |

Bad or parked domains to avoid (checked today): hondaridgeline.com (parked), mach-e.com (for sale), wpc-club.com (unrelated), miataclubofamerica.com (unrelated redirect), minimania.com, gmc-forum.com, ioniq5forum.com and ev6forum.com (no DNS).

---

## 6. What a non-cookie-cutter app looks like

**Positioning:** the family garage that never loses your history.

Ideas ranked by evidence that people pay:

| Idea | Pay signal | Notes |
|---|---|---|
| **Real family sharing, no account** (CloudKit CKShare per vehicle or whole garage; roles; each person logs their own fill-ups and services) | Strong. Road Trip MPG's Family Sharing; AUTOsist bought for "mine, wife's, and kid's"; Fuelly couples complain about sync | Nobody does this well. Jack already has a two-store CKShare recipe (reference_coredata_cloudkit_sharing). Add a per-person "hide costs" toggle. |
| **Durability guarantee**: iCloud plus free CSV/PDF export, imports from Fuelly, Drivvo, Simply Auto, Road Trip MPG and CARFAX CSV | Table stakes, and a migration wedge | Stale apps (Fuelly, Simply Auto, Car Minder) have stranded users. Import is the acquisition hook. SteerLog already claims this pitch. |
| **Receipt capture**: VisionKit document scanner plus on-device Vision OCR to pull date, odometer, shop, total and line items | Strong. "clunky entry" is the #1 friction; thermal receipts fade | Store the original image plus the parsed record. Scan-to-entry in under 10 seconds is the demo moment. |
| **Service Passport**: a beautiful PDF plus a share link and QR (in the glovebox or on a for-sale listing), showing a timeline, receipt thumbnails and a "documented by owner, receipts attached" badge | Medium-strong, at the selling moment. Binders for resale; the CARFAX DIY gap; a buyer knocking down price | A natural one-time unlock or Pro trigger. No Amazon links inside (Associates policy). Optionally hand the history to the buyer (Drivvo has a basic version). |
| **Odometer OCR** from a dashboard photo, plus estimated mileage from your own miles-per-day, confirmed occasionally | Medium | CARFAX auto-estimates and users hate wrong guesses. Offer a widget and Shortcut "update odometer". |
| **Wallet-style vehicle cards**: VIN (copyable, never masked), plate, insurance and registration expiry, tire size, oil spec, battery date. Optional Apple Wallet pass for the insurance card | Medium. AUTOsist's "glovebox" is loved; CARFAX masking the VIN drew complaints | Registration and insurance expiry reminders count as maintenance for families. |
| **Widgets / Lock Screen / Live Activity** ("Oil due in 412 mi"; a Live Activity during a shop visit or DIY job with a checklist and torque specs) | Low-medium (delight, retention) | Keep notifications sparse. Users snooze nagging reminders. |
| **Engine hours plus non-car assets** (RV generator, boat, mower, trailer) with unlimited assets | Medium for the long tail | AUTOsist's 5-vehicle cap; VMT users tracking generators. |
| **Recall watch** (NHTSA by year/make/model, with parkIt/OTA flags) | Table stakes | CARFAX users find recalls early this way. |
| **KBB "check value" deep link** with mileage and zip | Low pay, a nice touch | Don't show numbers. Link out. |
| **"Buy the right part" links** (oil spec, filter, wipers via Amazon search tag) | Small revenue | Needs an Approved Mobile Application, no WebView, disclosure. |

**Skip:** GPS trip tracking, AI mechanic chat (a sea of 2026 clones), community feeds, OBD hardware.

**Pricing evidence:** one-time and lifetime prices win hearts (Road Trip MPG $6.99; AUTOsist $20 "forever"; Simply Auto $29.99 lifetime). Paywalling export or adding ads to paid tiers produces 1-star reviews. Keep the core log and export free. Charge for sharing, unlimited vehicles, scanning and the passport, and offer a lifetime option next to annual.

**Design references:** Flighty (dense-but-calm status cards, Live Activities), Things (fast entry, zero chrome), Apple Wallet (stacked vehicle cards), Carrot Weather (personality in empty states, sparingly), Paku (one glanceable answer). The "garage" home screen should be a stack of vehicle cards with each car's color and silhouette and one line: what's next and when.
