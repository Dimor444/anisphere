# DM Deploy Manifest

Everything Direct Messages needs in production, in order. **Nothing here has
been deployed.** All DM work so far (Phases 1–4) was built and verified
against the local emulator suite only.

Project: `anisphere-36cb0` · region `europe-west1` · branch
`claude/anisphere-dm-audit-fa1a94`.

---

## 0. Before you start: the CLI is not currently usable

Two independent problems on this machine. Both must be handled or the deploy
will fail in confusing ways.

**(a) CLI auth is broken.** `firebase <anything>` fails with:

> Authentication Error: Your credentials are no longer valid. Please run
> `firebase login --reauth`

Verified 2026-08-03: the stored refresh token still mints a valid Bearer
token, but Google rejects it on Cloud-platform APIs with a misleading 401
`ACCESS_TOKEN_TYPE_UNSUPPORTED`. Fix it first, interactively:

```bash
firebase login --reauth
```

**(b) DNS is half-dead for `*.googleapis.com`.** The system resolver *hangs*
(does not fail) for a shifting subset of Google API hosts, so the CLI wedges
or times out. Run everything through the local dig-backed CONNECT proxy on
`127.0.0.1:3129` (see the `firebase-rules-deploy-workaround` note; the script
used on 2026-08-03 is reproducible in ~100 lines of python3). Start the proxy,
confirm it answers, then prefix every command with `HTTPS_PROXY`.

```bash
curl -sS -x http://127.0.0.1:3129 -o /dev/null -w "proxy ok: %{http_code}\n" --max-time 20 https://firebaserules.googleapis.com/
```

Proxy connects are individually flaky (the broken host set shifts), so retry
rather than concluding a step failed.

---

## 1. What must ship

Three artifacts, in this order. Rules and indexes are independent of the app
binary and should go out **before** a build carrying DM UI reaches users.

### 1.1 `firestore.rules` — the whole `conversations` block

Adds a top-level `conversations/{cid}` match plus its `messages/{mid}`
subcollection. Nothing in any pre-existing block was modified.

- create: 2 participants, caller included, full `hasOnly` key whitelist,
  server-stamped timestamps, born empty (`lastMessage`, `blockedBy`, `lastReadAt`)
- read: participants only
- update: exactly three branches — send (preview ≤ 120 chars, `updatedAt ==
  request.time`), own-key read receipt, add-or-remove-**self** `blockedBy`
- delete: denied
- `messages/{mid}`: participant read; create requires `senderId == auth.uid`,
  text ≤ 1000, text-or-image, server-stamped, and a **non-empty `blockedBy`
  freezes creates for both sides**; the single update branch is a participant
  toggling their **own** `reactions` key (emoji string ≤ 8, also frozen while
  blocked); delete own message only

`rules_version = '2'` is unchanged at the top of the file.

### 1.2 `firestore.indexes.json` — 2 new composite indexes

| collectionGroup | fields | serves |
|---|---|---|
| `conversations` | `participants` ARRAY_CONTAINS, `updatedAt` DESC | the inbox stream (`watchConversations`) |
| `messages` | `senderId` ASC, `createdAt` ASC | the unread aggregation (`unreadCount`) |

The five pre-existing indexes (posts, news, trueFanScores ×2, rooms) are
untouched and must survive the deploy — `firebase deploy` replaces the whole
index set from this file, so deploy the file as committed, never a subset.

> The Block List query (`blockedBy` array-contains, no orderBy) is
> single-field and needs **no** composite index.

### 1.3 `storage.rules` — the `dm_images` block

**This is the one people forget.** Production storage rules were last
released **2026-07-13** and do not know about DMs at all. Until this ships,
every image send fails with `storage/unauthorized`.

Adds `dm_images/{cid}/{fileName}`: participants only (the cid splits on `_`
into the two uids), JPEG only, `< 1 MB`, and immutable —
**`resource == null` on create**, because in Storage rules an overwrite
evaluates as *create* (a new object generation), not update; `update: false`
alone would not prevent overwrites. No client deletes.

> Caveat worth knowing before launch: the participant gate assumes uids never
> contain `_`, which holds for Firebase-generated uids. If custom-token uids
> with underscores are ever introduced, this check must change to an explicit
> participants lookup.

---

## 2. Deploy

Rules and indexes together, then storage. Index builds are asynchronous —
they can report success and still be `CREATING` for minutes on a large
collection (both DM indexes start empty, so they should be `READY` almost
immediately).

```bash
HTTPS_PROXY=http://127.0.0.1:3129 firebase deploy --only firestore:rules,firestore:indexes --project anisphere-36cb0 --non-interactive
```

```bash
HTTPS_PROXY=http://127.0.0.1:3129 firebase deploy --only storage --project anisphere-36cb0 --non-interactive
```

No Cloud Functions change in this release — the two Watch Party triggers
(`onRoomMemberJoined` / `onRoomMemberLeft`) are the only functions deployed
and DMs add none. Do **not** pass `--only functions`; unread counts are a
client-side `count()` aggregation by design.

---

## 3. Post-deploy verification (read the live state back)

Do not trust the deploy summary. Read each artifact back and compare against
the local file. `firebase firestore:rules` does not exist as a read command in
firebase-tools 15.x, so rules come back over REST.

**Get a token** (the CLI stores the refresh token; mint a Bearer from it):

```bash
firebase login:ci --no-localhost
```

Or reuse the refresh token in `~/.config/configstore/firebase-tools.json` via
the oauth2 token endpoint. On `firestore.googleapis.com` and
`cloudfunctions.googleapis.com` you must also send
`-H "x-goog-user-project: anisphere-36cb0"` or the call 401s misleadingly.

**3.1 Firestore rules — expect a byte-identical diff:**

```bash
curl -sS -x http://127.0.0.1:3129 -H "Authorization: Bearer $TOKEN" "https://firebaserules.googleapis.com/v1/projects/anisphere-36cb0/releases" | python3 -c "import json,sys; [print(r['name'], r['rulesetName'], r.get('updateTime')) for r in json.load(sys.stdin)['releases']]"
```

```bash
curl -sS -x http://127.0.0.1:3129 -H "Authorization: Bearer $TOKEN" "https://firebaserules.googleapis.com/v1/projects/anisphere-36cb0/rulesets/RULESET_ID" | python3 -c "import json,sys; print(json.load(sys.stdin)['source']['files'][0]['content'])" > /tmp/live_firestore.rules && diff firestore.rules /tmp/live_firestore.rules && echo "BYTE-IDENTICAL"
```

**3.2 Indexes — expect 7 total, all `state=READY`, including the 2 new ones:**

```bash
curl -sS -x http://127.0.0.1:3129 -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: anisphere-36cb0" "https://firestore.googleapis.com/v1/projects/anisphere-36cb0/databases/(default)/collectionGroups/-/indexes" | python3 -c "
import json,sys
for ix in json.load(sys.stdin).get('indexes', []):
    grp = ix['name'].split('/collectionGroups/')[1].split('/')[0]
    fields = ', '.join('%s %s' % (f['fieldPath'], f.get('order', f.get('arrayConfig',''))) for f in ix['fields'] if f['fieldPath'] != '__name__')
    print('%-15s state=%-9s [%s]' % (grp, ix.get('state'), fields))"
```

A `state=CREATING` on either DM index means queries will fail until it
finishes — re-run until both read `READY` before shipping the app build.

**3.3 Storage rules — same read-back, different release name.** The storage
release is keyed by bucket (`firebase.storage/anisphere-36cb0.firebasestorage.app`);
take its `rulesetName` from the releases listing in 3.1, then:

```bash
curl -sS -x http://127.0.0.1:3129 -H "Authorization: Bearer $TOKEN" "https://firebaserules.googleapis.com/v1/projects/anisphere-36cb0/rulesets/STORAGE_RULESET_ID" | python3 -c "import json,sys; print(json.load(sys.stdin)['source']['files'][0]['content'])" > /tmp/live_storage.rules && diff storage.rules /tmp/live_storage.rules && echo "BYTE-IDENTICAL"
```

Confirm the `updateTime` is today's — if it still reads `2026-07-13`, the
storage deploy did not take and image sends will fail in production.

---

## 4. Smoke test on a real device (after all three are live)

The emulator does not enforce composite indexes, so a missing index only
surfaces against production. Against a **production** build (plain
`flutter run`, no `USE_EMULATOR`), with two real accounts:

1. Open Messages → the inbox loads (proves the `conversations` index).
2. Open a thread, send text → appears, preview + ordering update in the list.
3. Send an image → uploads and renders (proves `storage.rules` shipped).
4. Long-press a message → react, change, remove.
5. Unread dot appears for the recipient and clears on open (proves the
   `messages` index behind `unreadCount`).
6. Block from the chat menu → both composers freeze; Settings → Block List
   shows the row; unblock restores sending.

If step 1 or 5 fails with a `failed-precondition` error mentioning an index,
the console error contains a direct creation link — but prefer fixing
`firestore.indexes.json` and redeploying so the repo stays the source of truth.
