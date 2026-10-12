# How Flighty works, and how Flightly maps to it

"Flightly" is modelled on **Flighty** (iOS flight tracker, Flighty LLC). All evidence below is from public sources fetched on 2026-10-12.
Flighty's binary was not decompiled (that needs an IPA from the App Store tied to an Apple ID); behaviour is inferred from its listing, help center and a review.

## Sources
- App Store listing: https://apps.apple.com/us/app/1358823008 (v4.11.1, iOS 18+, 4.8★ / 157K ratings, "No account required")
- Help center, importing flights: https://flighty.com/help/importing-flights
- MacStories review: https://www.macstories.net/reviews/flighty-a-pro-level-ios-app-for-frequent-travelers/

## Evidence → implementation
| Flighty behaviour (source) | Flightly implementation |
|---|---|
| Unlimited flights, flight log, map, all-time/annual stats are free (App Store) | `FlightsView`, `PassportView` |
| Live data, weather, actual route, aircraft model (App Store) | `LiveEngine.swift` (simulated), `FlightDetailView` |
| Pro: delay reasons + predictions (App Store) | "Why is it delayed?" card, `LiveState.delayReason/prediction` |
| Pro: 25-hour "Where's my plane" (App Store, MacStories) | `wheresMyPlane` – 3-leg inbound aircraft chain that drives late-aircraft delays |
| Pro: Arrival Forecast with route on-time stats (MacStories) | `forecastCard` bar chart (60-day route outcomes) |
| Pro: Delay Trend (App Store) | `trendCard` hourly delay chart |
| Pro: Live Activities, live lock-screen widgets, Dynamic Island (App Store) | `FlightlyWidgets/Widgets.swift`, `AppModel.startActivity` |
| Lock-screen widgets (free, limited refresh) | `NextFlightWidget` (home + lock screen families) |
| Pro: fastest push alerts; 4 categories Basics / Above & Beyond / Flight Plan / Arrival (MacStories) | Settings toggles + `AppModel.refresh` change detection → local notifications |
| Pro: Connection Assistant (App Store) | `connectionCard` (layover vs. typical minimum + terminal walk) |
| Assistants: Morning-Of, Check-In (App Store) | `assistantsCard`, scheduled reminders |
| Record of changes (MacStories) | `Flight.changes`, `changesCard` |
| Taxi times, tail number, airport details (App Store) | gates/timeline/aircraft cards |
| Flighty Friends (App Store) | `FriendsView`, `flightly://friend?d=…` share links |
| Passport: map, countries, stats (App Store) | `PassportView` (routes + heat map, countries, top airports, share card) |
| Airport Status Map, disruption list, METAR/TAF reasons, flight boards, hourly performance, favorites, Runway Regulars (App Store) | `AirportsView`, `AirportDetailView` |
| Import: myFlightRadar24, OpenFlights, App in the Air, … (Help) | `CSVImporter` (auto-detects OpenFlights / myFlightRadar24 columns). **No 365-day cap** |
| Calendar sync, TripIt sync, email forwarding (Help/App Store; Pro) | `CalendarSync` (EventKit), `ICSImporter` (TripIt iCal feed), `TextFlightParser` (pasted email) |
| Manual "add missing flight" with only airports + date (Help) | "Past flight" tab in `AddFlightView` |
| Edit past flights, notes, data export (App Store) | `EditFlightView`, notes card, CSV export |
| Siri: flight status, next gate (App Store) | `FlightIntents.swift` (App Intents) |
| "Crew" travel reason reduces alerts (App Store) | `TravelReason.crew` |
| Two alternate app icons (App Store) | `AppIconNight`, `AppIconSunrise` |

## Not built (and why)
- Real live data: no flight-data API key. `FlightDataProvider` is the seam to plug one in.
- Apple Watch app/complications, CarPlay, Mac, Vision: out of scope for this iPhone build.
- iCloud sync: needs a paid developer team/CloudKit container.
- Server-side email forwarding address and remote push: needs a backend.
- Subscriptions: intentionally absent; everything Pro is on.

## UI evidence (second pass)
Method: REA could not reach Flighty's iOS UI (that needs the app's IPA, which requires an Apple ID; `analyze-web-bundle` needs a Chrome debug endpoint and only covers the marketing site). The UI was instead modelled from Flighty's six official App Store screenshots and flighty.com / flighty.com/passport, viewed in the in-app browser.

| Observed | Where it shows up in Flightly |
|---|---|
| Home = 3D satellite globe with blue route arcs, white bottom sheet "My Flights ⌄", share button + avatar, "Search to add flights" field, three round map buttons | `FlightsView` (custom 3-detent sheet, `MapStyle.imagery(.realistic)`, geodesic arcs) |
| Flat rows: airline mark, "AA 1001", "Tokyo to San Francisco", airport chips with status glyph, green "Landing in 3h 30m", amber "55m at JFK / Tight", date for future flights, "IN AIR" / countdown at left | `FlightRow` |
| iOS 26 Liquid Glass tab bar: Flights, Friends, Passport + separate round search button | `RootView` (`Tab(role: .search)`) |
| Friends' Flights: title dropdown, share + avatar, search field, "All" + avatar chips, rows with avatars and IN AIR | `FriendsView` |
| "Where's My Plane?" card: sky header, aircraft + tail, red RUNNING LATE badge, "35m delay predicted…", "My Flight / 35m Delay Predicted", inbound legs with "52m Late" | `FlightDetailView.wheresMyPlane` |
| ATC notice card: "JFK Arrivals — 1h 10m delay", red "Flights to JFK Grounded", "Advisory from Air Traffic Control" | `FlightDetailView.notices` |
| Live Activity: "SFO 11:00AM ✈ 12:00PM JFK", "T3 • On Time", gauge, "1h 20m UNTIL GATE ARRIVAL", confirmation code; Dynamic Island with green timer and amber gate chip | `Widgets.swift` |
| Passport: deep violet, ALL TIME / year chips, route ticker, passport card with MRZ line, split-flap "Lost to delays", Delay Report, aircraft card | `PassportView` |
| Typography: system font, bold, tight (computed `font-family` on flighty.com is the system stack, h1 700) | `Font.f(_:_:)` uses SF everywhere |

Inferred (not directly visible): exact left-column countdown format, exact hex colours (sampled by eye), spring timings, layout of screens not shown in public marketing (Add flow, Settings, Airports). Airline logos are replaced by neutral monogram tiles (trademarks).

## Passport (third pass, from screenshots of the real app supplied by the user)
Observed: Passport reuses the Flights scaffold (globe + sheet) with title "Passport", outlined share button, sky-blue initials avatar, "All-Time / 2025" chips (selected = white pill with hairline + shadow); three gradient cards (indigo "ALL-TIME FLIGHTY PASSPORT" with FLIGHTS / DISTANCE / FLIGHT TIME / AIRPORTS / AIRLINES and "4 Long Haul", "1.2x around the world"; red "12 hours lost from delays" + "Delayed flights averaged 1h 59m late"; lavender "Most flown aircraft" with photo) each ending in a translucent "All … Stats ›" button; "Past Flights" with list/grid toggle, sort chips (Date ↓ / From / To / Airline / Aircraft), year headers with "9 FLIGHTS", and large-logo rows (caption "AA 2772 JFK → AUS", 20pt title, date at right). Partial sheet detents float with side/bottom margins and run under the Liquid Glass tab bar (tab labelled "My Flights"); the large detent is edge to edge below a black status area. A PRO upsell banner ("Upgrade to add flights older than 12 months") exists in Flighty and is intentionally omitted here.
Implemented in `MapSheet.swift` (shared scaffold), `PassportView.swift`, `FlightsView.swift`.
