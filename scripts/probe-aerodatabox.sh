#!/usr/bin/env bash
# Probes your AeroDataBox (RapidAPI) plan with ~5 requests and saves the raw responses to .probe/ (gitignored),
# so Flightly's client can be written against what your plan actually returns.
#
#   export RAPIDAPI_KEY="<your key>"      # from the RapidAPI "Authorization" tab; never paste it into chat or commit it
#   scripts/probe-aerodatabox.sh
set -u
: "${RAPIDAPI_KEY:?Set RAPIDAPI_KEY first (export RAPIDAPI_KEY=...)}"
HOST="aerodatabox.p.rapidapi.com"
OUT=".probe"; mkdir -p "$OUT"
TODAY=$(date -u +%Y-%m-%d)

call() {   # call <name> <path>
  local name="$1" path="$2"
  curl -sS -m 30 -D "$OUT/$name.headers" -o "$OUT/$name.json" -w "%{http_code}" \
    -H "X-RapidAPI-Key: $RAPIDAPI_KEY" -H "X-RapidAPI-Host: $HOST" "https://$HOST$path" > "$OUT/$name.status" 2>"$OUT/$name.err"
  printf "%-18s HTTP %s  (%s bytes)\n" "$name" "$(cat "$OUT/$name.status")" "$(wc -c < "$OUT/$name.json" | tr -d ' ')"
}

# 1. Flight status, nearest date — try a flight number that flies daily (your page used KL1395)
call flight_status      "/flights/number/KL1395?withAircraftImage=false&withLocation=true"
# 2. Airport departures board (small 2-hour window) — used for flight boards
call airport_fids       "/flights/airports/iata/AMS/${TODAY}T12:00/${TODAY}T14:00?withLeg=true&direction=Departure&withCancelled=true&withCodeshared=false&withCargo=false&withPrivate=false"
# 3. Airport delay statistics — used for hourly performance / delay trend
call airport_delays     "/airports/iata/AMS/delays"
# 4. Aircraft by registration (use the registration printed in call 1, or this example)
call aircraft_reg       "/aircrafts/reg/PH-BXA"
# 5. Airport info (timezone, coordinates) — used to replace the hardcoded airport list
call airport_info       "/airports/iata/AMS"

echo; echo "Quota headers from the last call:"; grep -i -E "x-ratelimit|x-rapidapi" "$OUT/airport_info.headers" || echo "(none found)"
echo; echo "Done. Raw responses are in $OUT/ — tell Claude it finished (do not paste your key)."
