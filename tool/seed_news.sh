#!/usr/bin/env bash
# Seed the production `news` collection via the Firestore REST API.
#
# The collection is create-locked for clients (see firestore.rules) — writes
# must come from an owner credential. This uses the firebase-tools OAuth
# token, which goes through IAM and bypasses security rules.
#
# Usage: tool/seed_news.sh            # seeds the sample articles below
# Re-run safe-ish: articles are created with fixed doc ids, so re-running
# overwrites the same five docs instead of duplicating them.
set -euo pipefail

PROJECT="anisphere-36cb0"
BASE="https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents"

# Refresh + extract the firebase-tools access token.
firebase projects:list --project "$PROJECT" >/dev/null 2>&1 || true
TOKEN=$(python3 - <<'PY'
import json, pathlib
cfg = json.load(open(pathlib.Path.home() / ".config/configstore/firebase-tools.json"))
print(cfg["tokens"]["access_token"])
PY
)

seed() { # id  json-fields
  local id="$1" fields="$2"
  curl -sf -X PATCH "${BASE}/news/${id}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"fields\": ${fields}}" >/dev/null \
    && echo "  ✓ news/${id}" || echo "  ✗ news/${id} FAILED"
}

ts() { date -u -v-"$1"H +"%Y-%m-%dT%H:%M:%SZ"; } # $1 hours ago

echo "Seeding news into ${PROJECT}…"

seed "seed-frieren-s2" "{
  \"title\": {\"stringValue\": \"Frieren: Beyond Journey's End Season 2 premieres January 2026\"},
  \"description\": {\"stringValue\": \"Madhouse returns with the continuation of the highest-rated anime of the decade. The new season adapts the First-Class Mage Exam arc conclusion and beyond.\"},
  \"category\": {\"stringValue\": \"Season\"},
  \"source\": {\"stringValue\": \"AniSphere\"},
  \"animeIds\": {\"arrayValue\": {\"values\": [{\"integerValue\": \"154587\"}]}},
  \"animeTitles\": {\"arrayValue\": {\"values\": [{\"stringValue\": \"Frieren\"}]}},
  \"publishedAt\": {\"timestampValue\": \"$(ts 2)\"},
  \"views\": {\"integerValue\": \"0\"}, \"saves\": {\"integerValue\": \"0\"}
}"

seed "seed-csm-movie" "{
  \"title\": {\"stringValue\": \"Chainsaw Man – The Movie: Reze Arc — global theatrical release dates announced\"},
  \"description\": {\"stringValue\": \"MAPPA's first Chainsaw Man film brings the fan-favorite Bomb Girl arc to theaters worldwide.\"},
  \"category\": {\"stringValue\": \"Movie\"},
  \"source\": {\"stringValue\": \"MAPPA\"},
  \"animeIds\": {\"arrayValue\": {\"values\": [{\"integerValue\": \"127230\"}]}},
  \"animeTitles\": {\"arrayValue\": {\"values\": [{\"stringValue\": \"Chainsaw Man\"}]}},
  \"publishedAt\": {\"timestampValue\": \"$(ts 8)\"},
  \"views\": {\"integerValue\": \"0\"}, \"saves\": {\"integerValue\": \"0\"}
}"

seed "seed-op-egghead" "{
  \"title\": {\"stringValue\": \"One Piece: Egghead arc finale — Toei teases 'biggest animation production yet'\"},
  \"description\": {\"stringValue\": \"The Egghead Island climax gets a production spotlight, with staff from the Wano arc returning for the final episodes.\"},
  \"category\": {\"stringValue\": \"Announcement\"},
  \"source\": {\"stringValue\": \"Toei Animation\"},
  \"animeIds\": {\"arrayValue\": {\"values\": [{\"integerValue\": \"21\"}]}},
  \"animeTitles\": {\"arrayValue\": {\"values\": [{\"stringValue\": \"One Piece\"}]}},
  \"publishedAt\": {\"timestampValue\": \"$(ts 20)\"},
  \"views\": {\"integerValue\": \"0\"}, \"saves\": {\"integerValue\": \"0\"}
}"

seed "seed-jjk-collab" "{
  \"title\": {\"stringValue\": \"Jujutsu Kaisen x UNIQLO UT collection drops this month\"},
  \"description\": {\"stringValue\": \"A new apparel collaboration featuring Gojo, Yuji and Sukuna artwork from the Shibuya Incident arc.\"},
  \"category\": {\"stringValue\": \"Collab\"},
  \"source\": {\"stringValue\": \"UNIQLO\"},
  \"animeIds\": {\"arrayValue\": {\"values\": [{\"integerValue\": \"113415\"}]}},
  \"animeTitles\": {\"arrayValue\": {\"values\": [{\"stringValue\": \"Jujutsu Kaisen\"}]}},
  \"publishedAt\": {\"timestampValue\": \"$(ts 30)\"},
  \"views\": {\"integerValue\": \"0\"}, \"saves\": {\"integerValue\": \"0\"}
}"

seed "seed-anime-expo" "{
  \"title\": {\"stringValue\": \"Anime Expo 2026 opens ticket sales — AniSphere community meetup confirmed\"},
  \"description\": {\"stringValue\": \"Los Angeles, July 2–5. Industry panels from MAPPA, ufotable and Madhouse are on the schedule.\"},
  \"category\": {\"stringValue\": \"Event\"},
  \"source\": {\"stringValue\": \"AniSphere\"},
  \"publishedAt\": {\"timestampValue\": \"$(ts 48)\"},
  \"views\": {\"integerValue\": \"0\"}, \"saves\": {\"integerValue\": \"0\"}
}"

echo "Done."
