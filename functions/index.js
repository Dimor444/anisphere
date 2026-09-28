/**
 * AniSphere Cloud Functions.
 *
 * Home for writes the client is not trusted to make. Security rules deny
 * direct client writes to counters like rooms/{roomId}.memberCount, so the
 * only thing that moves them is a trigger in here. The same principle covers
 * anything the client must not be able to decide for itself — including
 * whether it is allowed to upload another video, which is why the R2
 * presigner below lives here rather than in the app.
 */

const { onDocumentCreated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onTaskDispatched } = require('firebase-functions/v2/tasks');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFunctions } = require('firebase-admin/functions');
const { getStorage } = require('firebase-admin/storage');
const { getFirestore, FieldValue, FieldPath, Timestamp } = require('firebase-admin/firestore');
const { randomInt, randomUUID } = require('node:crypto');
const { S3Client, PutObjectCommand, DeleteObjectCommand, ListObjectsV2Command } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');

initializeApp();

const db = getFirestore();

/**
 * Recomputes rooms/{roomId}.memberCount from the members subcollection.
 *
 * Deliberately NOT a ±1 delta. Cloud Functions deliver at-least-once, and the
 * emulator demonstrably redelivers a create event AFTER the matching delete —
 * a delta-based handler double-counts that join and the room is left with a
 * count no subsequent event repairs. Deriving the count from the docs makes
 * the handler idempotent (a redelivery recomputes the same number), order-
 * independent, and self-healing: any drift is corrected by the next event.
 * It also removes the need to floor at 0, since a count is never negative.
 *
 * The read and the write share a transaction so concurrent joins can't
 * interleave into a lost update. A room deleted out from under its members is
 * a no-op, not an error.
 *
 * A count of zero ENDS the room: a watch party nobody is in is not a room, and
 * left standing it would sit in everyone's list forever. The recount reads the
 * live subcollection inside the transaction, so a leave that races a rejoin
 * only deletes if the room is really empty at that instant — and the rules
 * refuse a join into a room that no longer exists. Returns true when it ended
 * the room.
 */
async function syncMemberCount(roomId) {
  const roomRef = db.collection('rooms').doc(roomId);
  return db.runTransaction(async (tx) => {
    const room = await tx.get(roomRef);
    if (!room.exists) return false;

    const members = await tx.get(roomRef.collection('members').count());
    const actual = members.data().count;

    if (actual === 0) {
      tx.delete(roomRef);
      return true;
    }
    // Skip the write when already correct — most redeliveries land here.
    if (room.get('memberCount') === actual) return false;
    tx.update(roomRef, { memberCount: actual });
    return false;
  });
}

exports.onRoomMemberJoined = onDocumentCreated('rooms/{roomId}/members/{uid}', (event) =>
  syncMemberCount(event.params.roomId),
);

exports.onRoomMemberLeft = onDocumentDeleted('rooms/{roomId}/members/{uid}', async (event) => {
  const { roomId } = event.params;
  if (await syncMemberCount(roomId)) {
    console.log(JSON.stringify({ severity: 'INFO', event: 'room-ended-empty', roomId }));
  }
});

/**
 * A deleted room takes its roster with it. Deleting a document does NOT delete
 * its subcollections, so a host ending a room from the client would otherwise
 * leave members/ behind — orphans that still match each member's
 * collection-group lookups. Each deletion here fires onRoomMemberLeft, which
 * finds no room and does nothing.
 */
exports.onRoomDeleted = onDocumentDeleted('rooms/{roomId}', (event) =>
  db.recursiveDelete(db.collection('rooms').doc(event.params.roomId).collection('members')),
);

// A room nobody has joined for this long is ended by the sweep below. There is
// no presence signal: a member whose app was killed never runs the leave, so
// their membership outlives them and the room reads "1 watching" to everyone.
// Six hours is past any single sitting, and a room people keep joining lives on.
const ROOM_IDLE_MS = 6 * 60 * 60 * 1000;

/**
 * Ends rooms that are over ROOM_IDLE_MS old and have had no join in that long.
 * It is also what clears the rooms from before leaving existed: every one of
 * them is older than the cutoff, and their memberships are all stale.
 */
async function sweepStaleRooms(now = Date.now()) {
  const cutoff = Timestamp.fromMillis(now - ROOM_IDLE_MS);
  const old = await db.collection('rooms').where('createdAt', '<', cutoff).get();
  const ended = [];
  for (const room of old.docs) {
    const recent = await room.ref.collection('members').where('joinedAt', '>=', cutoff).limit(1).get();
    if (!recent.empty) continue;
    await db.recursiveDelete(room.ref);
    ended.push(room.id);
  }
  if (ended.length) {
    console.log(JSON.stringify({ severity: 'INFO', event: 'rooms-swept', count: ended.length, roomIds: ended }));
  }
  return ended;
}

exports.sweepStaleRooms = onSchedule(
  { schedule: 'every 1 hours', timeZone: 'Etc/UTC', region: 'europe-west1' },
  () => sweepStaleRooms(),
);

// Exported for test/member_count.test.js: redelivery of a single event is the
// case this design exists for, and no amount of driving Firestore reproduces
// it on demand. Calling the body directly does.
exports._syncMemberCount = syncMemberCount;
exports._sweepStaleRooms = sweepStaleRooms;

// ── Ani Videos → Cloudflare R2 ─────────────────────────────────────────────

// Not secrets: the account id and bucket appear in every signed URL, and the
// public base is handed to every reader. Keeping them in code (rather than in
// Secret Manager) means the client can be told the read base by this function
// instead of hardcoding it, and a bucket change is a normal code review.
const R2_ACCOUNT_ID = 'a33179ee6313a7a924e3e002827983bb';
const R2_BUCKET = 'anisphere-videos';
const R2_PUBLIC_BASE = 'https://pub-d6e4c414f2c04681bbafc54bd2375308.r2.dev';

// Secrets live in Cloud Secret Manager and are bound per function via the
// `secrets` option below. Their `.value()` resolves at RUNTIME only — reading
// it at module scope would run during deployment analysis, where no secret is
// mounted, so the S3 client is constructed inside the handler.
const R2_ACCESS_KEY_ID = defineSecret('R2_ACCESS_KEY_ID');
const R2_SECRET_ACCESS_KEY = defineSecret('R2_SECRET_ACCESS_KEY');

// Presigned PUTs are short-lived: long enough for a large upload on a poor
// connection, short enough that a leaked URL is not a standing write grant.
const UPLOAD_URL_TTL_SECONDS = 600;

// Hard ceiling on a clip's bytes, mirrored by AniVideoData.maxUploadBytes.
//
// This is the ONLY size limit that exists. Firebase Storage's rule capped
// video at 50 MB and went away with the migration; R2 enforces nothing on its
// own, and a 62.75 MB file has already reached production through the gap.
// The client checks the length before asking for a url, but a client check is
// a suggestion — the number below is signed into the presigned PUT, so R2
// itself refuses a body of any other size.
const MAX_UPLOAD_BYTES = 150 * 1024 * 1024;
const MAX_UPLOAD_MB = 150;

// Server-only ledger of issued upload grants, one document per signed pair.
// Nothing client-side may read or write it (firestore.rules denies the whole
// collection outright); the Admin SDK bypasses rules, so this function is its
// only author.
const GRANTS = 'upload_grants';

// Upload caps per tier. Both limits apply — the daily limit throttles bursts,
// the total limit bounds what one account can ever cost.
const TIER_CAPS = {
  guest: { perDay: 3, total: 10 },
  signed: { perDay: 10, total: 100 },
  plus: { perDay: 30, total: 500 },
};

// Firestore auto-ids are exactly 20 characters from [A-Za-z0-9]. The id is
// interpolated straight into the R2 object key, so this is the boundary that
// stops `../` (and anything else) from escaping the caller's own prefix.
// Anchored deliberately: in JS `$` (without the `m` flag) matches only the end
// of the string, so a trailing newline cannot smuggle a second segment past it.
const FIRESTORE_ID = /^[A-Za-z0-9]{20}$/;

/**
 * Midnight UTC for the instant `now` falls in.
 *
 * UTC rather than the caller's local day: the client controls its own clock
 * and timezone, so a local-day boundary would let a device roll its own reset
 * by changing timezone. Everyone shares one reset instant.
 */
function startOfUtcDay(now) {
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}

/// "YYYY-MM-DD" in UTC — the same day key the streak uses on the client
/// (CommunityVoteService.dayIdFor) and the rules use in serverDay().
function utcDayId(now) {
  return startOfUtcDay(now).toISOString().slice(0, 10);
}

/// Midnight UTC after [now] — when the next daily allowance opens.
function nextUtcMidnight(now) {
  const d = startOfUtcDay(now);
  d.setUTCDate(d.getUTCDate() + 1);
  return d;
}

/**
 * The caller's tier.
 *
 * Anonymous wins over everything: an anonymous session is free and unlimited
 * to mint, so it gets the guest caps even in the (contradictory) case where
 * its user doc carries isPlus. isPlus itself is server-managed — firestore
 * .rules forbids the client from ever writing it — so trusting it here is
 * safe in a way that trusting a client-sent tier would not be.
 */
function tierOf(auth, userDoc) {
  const provider = auth.token && auth.token.firebase && auth.token.firebase.sign_in_provider;
  if (provider === 'anonymous') return 'guest';
  if (userDoc.exists && userDoc.get('isPlus') === true) return 'plus';
  return 'signed';
}

/**
 * Issues presigned R2 PUT urls for one Ani Video (clip + thumbnail).
 *
 * The client allocates the Firestore document id first and passes it in, so
 * the object key is known before any byte moves and the two halves — the
 * document and the objects — share one identity without a round trip.
 *
 * Caps count GRANTS ISSUED, not videos committed. Counting ani_videos looks
 * equivalent and is not: the document is written by the client only after the
 * bytes land, so a caller that uploads and simply never commits stays at count
 * zero and can loop forever. The billable event is the signed url, so the
 * signed url is what gets counted — the ledger entry goes in before the caller
 * ever sees a url, and it is what the next call reads back.
 *
 * The count is still recomputed from documents on every call rather than read
 * from a stored counter — same reasoning as syncMemberCount above: a derived
 * number is idempotent and self-healing, where a counter drifts on any retry,
 * crash, or concurrent call and never repairs itself.
 *
 * Consequence worth knowing: grants are never deleted, so the total cap is a
 * lifetime ceiling on upload ATTEMPTS. Deleting a video does not give the
 * quota back. That is deliberate — the cost being capped is bytes written,
 * which deleting the document does not refund.
 *
 * Region is pinned explicitly. Nothing in this file inherits europe-west1
 * from the two triggers above; region is a per-function deploy-time property,
 * and an unpinned function silently lands in us-central1.
 */
exports.requestVideoUploadUrl = onCall(
  {
    region: 'europe-west1',
    secrets: [R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in to upload a video.');
    }
    const uid = request.auth.uid;

    const videoId = request.data && request.data.videoId;
    if (typeof videoId !== 'string' || !FIRESTORE_ID.test(videoId)) {
      throw new HttpsError('invalid-argument', 'videoId must be a 20-character Firestore id.');
    }

    // Integer check before the range check: a float, a numeric string or a
    // NaN would otherwise slip past `>` and get signed into the url.
    const contentLength = request.data.contentLength;
    if (!Number.isInteger(contentLength) || contentLength <= 0) {
      throw new HttpsError('invalid-argument', 'contentLength must be a positive integer.');
    }
    if (contentLength > MAX_UPLOAD_BYTES) {
      // out-of-range rather than invalid-argument: the client maps this (like
      // resource-exhausted) to a readable limit message with no retry offered.
      throw new HttpsError(
        'out-of-range',
        `Video is too large (${Math.round(contentLength / 1024 / 1024)} MB). ` +
          `The limit is ${MAX_UPLOAD_MB} MB.`,
      );
    }

    const userDoc = await db.collection('users').doc(uid).get();
    // No profile, no upload. tierOf would read a missing profile as "not plus"
    // and carry on — which is how an account being deleted, whose profile is
    // gone but whose ID token lives up to an hour past revocation, could still
    // be handed a url that lands an object in R2 after the deletion has swept
    // it. The other callables that spend or earn already refuse here; this
    // one is the same refusal. A legitimate user can reach it only when the
    // app's fire-and-forget ensureProfile failed at launch, and the client
    // answers not-found by creating the profile and asking once more.
    if (!userDoc.exists) {
      throw new HttpsError('not-found', 'No profile for this account.');
    }
    const tier = tierOf(request.auth, userDoc);
    const caps = TIER_CAPS[tier];

    // Both counts are COUNT aggregations, not document reads: Firestore bills
    // them by index entries scanned, so enforcing the cap stays cheap even at
    // the 500-grant ceiling.
    const mine = db.collection(GRANTS).where('uid', '==', uid);
    const [totalSnap, todaySnap] = await Promise.all([
      mine.count().get(),
      mine
        .where('issuedAt', '>=', Timestamp.fromDate(startOfUtcDay(new Date())))
        .count()
        .get(),
    ]);
    const total = totalSnap.data().count;
    const today = todaySnap.data().count;

    if (total >= caps.total) {
      throw new HttpsError(
        'resource-exhausted',
        `Upload limit reached (${caps.total} videos for ${tier}).`,
      );
    }
    if (today >= caps.perDay) {
      throw new HttpsError(
        'resource-exhausted',
        `Daily upload limit reached (${caps.perDay} per day for ${tier}).`,
      );
    }

    // R2 is S3-compatible but has no regions; 'auto' is what it expects.
    //
    // requestChecksumCalculation is pinned because the SDK's default
    // ('WHEN_SUPPORTED') adds x-amz-checksum-crc32 to a presigned PUT — and
    // with no body present at signing time, that checksum is of ZERO bytes.
    // It rides inside the signature, so a client cannot strip it. Uploads work
    // today only because R2 declines to validate it; that is a dependency on
    // someone else's leniency, not a design. 'WHEN_REQUIRED' omits it.
    const s3 = new S3Client({
      region: 'auto',
      endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
      requestChecksumCalculation: 'WHEN_REQUIRED',
      credentials: {
        accessKeyId: R2_ACCESS_KEY_ID.value(),
        secretAccessKey: R2_SECRET_ACCESS_KEY.value(),
      },
    });

    // ContentType is what the object serves back on read, and video_player
    // infers the container from that response header — an unlabelled object
    // plays as nothing. Note it is NOT signed: presigning a PutObject leaves
    // X-Amz-SignedHeaders as `host` alone, so the stored type is whatever the
    // client sends. It must still be sent, but it is not enforced.
    //
    // ContentLength IS signed — supplying it puts `content-length` into
    // X-Amz-SignedHeaders and changes the signature, so R2 rejects a PUT
    // whose declared length differs. That is what turns the size cap from a
    // client-side suggestion into something the storage layer enforces. It is
    // signed for the clip only: the thumbnail is generated after this call,
    // so its length cannot be known here.
    const sign = (key, contentType, length) =>
      getSignedUrl(
        s3,
        new PutObjectCommand({
          Bucket: R2_BUCKET,
          Key: key,
          ContentType: contentType,
          ...(length == null ? {} : { ContentLength: length }),
        }),
        { expiresIn: UPLOAD_URL_TTL_SECONDS },
      );

    // Key layout mirrors the Firebase Storage paths it replaces, so the uid
    // prefix keeps one caller's objects out of another's namespace.
    const videoKey = `ani_videos/${uid}/${videoId}.mp4`;
    const thumbnailKey = `ani_videos/${uid}/${videoId}.jpg`;
    const [videoUrl, thumbnailUrl] = await Promise.all([
      sign(videoKey, 'video/mp4', contentLength),
      sign(thumbnailKey, 'image/jpeg', null),
    ]);

    // The ledger entry lands BEFORE the caller sees a url, and it is awaited:
    // if this write fails the error propagates and no url is ever returned, so
    // the failure mode is a refused upload rather than an uncounted one.
    //
    // The id is derived, not random. A repeat request for the same videoId
    // rewrites its own row instead of appending a second one, so a client
    // retrying the same upload cannot inflate its own count — the same
    // reasoning that makes likes/{uid} self-deduplicating. Signing is pure
    // local crypto with no network call, so ordering it before this write
    // costs nothing and avoids burning quota on a signature that never
    // materialised.
    await db
      .collection(GRANTS)
      .doc(`${uid}_${videoId}`)
      .set({
        uid,
        videoId,
        tier,
        // Server time, not the caller's. A client-supplied timestamp would let
        // a device backdate its own grants straight out of the daily window.
        issuedAt: FieldValue.serverTimestamp(),
        videoKey,
        thumbnailKey,
      });

    return {
      videoId,
      tier,
      // Handed back so the client composes `${publicBase}/${key}` rather than
      // carrying a second copy of the bucket's public hostname.
      publicBase: R2_PUBLIC_BASE,
      expiresInSeconds: UPLOAD_URL_TTL_SECONDS,
      // contentLength is echoed back so the client PUTs the value that was
      // actually signed rather than re-measuring the file and risking a
      // different number.
      video: {
        key: videoKey,
        uploadUrl: videoUrl,
        contentType: 'video/mp4',
        contentLength,
      },
      thumbnail: { key: thumbnailKey, uploadUrl: thumbnailUrl, contentType: 'image/jpeg' },
      usage: { tier, total, today, maxTotal: caps.total, maxPerDay: caps.perDay },
    };
  },
);

/**
 * Deletes one Ani Video's objects (clip + thumbnail) from R2.
 *
 * Deletion has to be server-side for the same reason uploads are: the R2
 * credentials must never reach a client. There is no presigned equivalent
 * worth issuing here — a presigned DELETE is a bearer token for destroying an
 * object, and the ownership question is exactly what a client cannot be
 * trusted to answer.
 *
 * Ownership is checked against the ani_videos document BEFORE anything is
 * removed, so the caller must both own the video and have it still exist. A
 * missing document is refused rather than treated as success: the client
 * deletes objects first and the document second (see AniVideoService
 * .deleteVideo), so in the legitimate flow the document is always still there.
 *
 * The upload_grants row is deliberately left alone. Quota is spent when bytes
 * are written, and deleting the bytes does not un-write them — the same
 * decision recorded on requestVideoUploadUrl.
 */
exports.deleteVideoObjects = onCall(
  {
    region: 'europe-west1',
    secrets: [R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in to delete a video.');
    }
    const uid = request.auth.uid;

    const videoId = request.data && request.data.videoId;
    if (typeof videoId !== 'string' || !FIRESTORE_ID.test(videoId)) {
      throw new HttpsError('invalid-argument', 'videoId must be a 20-character Firestore id.');
    }

    const doc = await db.collection('ani_videos').doc(videoId).get();
    if (!doc.exists) {
      throw new HttpsError('not-found', 'No such video.');
    }
    if (doc.get('userId') !== uid) {
      throw new HttpsError('permission-denied', 'Only the author may delete this video.');
    }

    // Same client config as the presigner above — see there for why
    // requestChecksumCalculation is pinned. (A single-object delete carries no
    // payload to checksum; it is set here so the two never drift.)
    const s3 = new S3Client({
      region: 'auto',
      endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
      requestChecksumCalculation: 'WHEN_REQUIRED',
      credentials: {
        accessKeyId: R2_ACCESS_KEY_ID.value(),
        secretAccessKey: R2_SECRET_ACCESS_KEY.value(),
      },
    });

    // uid, not doc.userId — they are equal by the check above, and using the
    // verified caller keeps the key derivation tied to the identity that was
    // actually authorised.
    const videoKey = `ani_videos/${uid}/${videoId}.mp4`;
    const thumbnailKey = `ani_videos/${uid}/${videoId}.jpg`;

    // S3 delete is idempotent — removing an absent key succeeds — so a retry
    // after a partial failure is safe and converges.
    await Promise.all([
      s3.send(new DeleteObjectCommand({ Bucket: R2_BUCKET, Key: videoKey })),
      s3.send(new DeleteObjectCommand({ Bucket: R2_BUCKET, Key: thumbnailKey })),
    ]);

    return { videoId, deleted: [videoKey, thumbnailKey] };
  },
);

// ── Anime metadata cache (anime_meta/{anilistId}) ──────────────────────────

// Shared, server-owned metadata so the app stops needing AniList reachable at
// render time. Today it is not: AniList returns a global 403 —
// "The AniList API has been temporarily disabled due to severe stability
// issues" — and every screen that resolves an anime by id degrades or empties.
//
// Only PERMANENT and SLOW fields live here. averageScore, popularity,
// favourites and nextAiringEpisode are deliberately absent: Chart and
// Observatory exist to show those numbers moving, so a cached copy would not
// be stale data, it would be wrong data presented as a ranking.
const ANIME_META = 'anime_meta';

// 30 days. Everything stored here is either immutable (id, titles, genres,
// seasonYear, format, countryOfOrigin, isAdult) or changes on the scale of a
// broadcast season (description, episodes, status).
const ANIME_META_TTL_MS = 30 * 24 * 60 * 60 * 1000;

// AniList caps Page.perPage at 50, so one call is at most one upstream
// request. This is also the per-call id cap — the two are the same number on
// purpose, so a caller can never force fan-out.
const ANIME_META_MAX_IDS = 50;

const ANILIST_ENDPOINT = 'https://graphql.anilist.co';
const ANILIST_TIMEOUT_MS = 10000;

// Requests exactly the stored fields and nothing else — asking for
// averageScore here would invite someone to persist it later.
const ANILIST_META_QUERY = `
query (\$ids: [Int]) {
  Page(perPage: ${ANIME_META_MAX_IDS}) {
    media(id_in: \$ids, type: ANIME) {
      id
      title { english romaji native }
      coverImage { large extraLarge color }
      genres
      seasonYear
      format
      countryOfOrigin
      isAdult
      description(asHtml: false)
      episodes
      status
    }
  }
}`;

/** One AniList media node → the stored document body (no fetchedAt). */
function metaFromMedia(m) {
  const title = m.title || {};
  const cover = m.coverImage || {};
  return {
    anilistId: m.id,
    titleEnglish: title.english ?? null,
    titleRomaji: title.romaji ?? null,
    titleNative: title.native ?? null,
    coverLarge: cover.large ?? null,
    coverExtraLarge: cover.extraLarge ?? null,
    coverColor: cover.color ?? null,
    genres: Array.isArray(m.genres) ? m.genres : [],
    seasonYear: m.seasonYear ?? null,
    format: m.format ?? null,
    countryOfOrigin: m.countryOfOrigin ?? null,
    isAdult: m.isAdult === true,
    description: m.description ?? null,
    episodes: m.episodes ?? null,
    status: m.status ?? null,
  };
}

/**
 * Fetches [ids] from AniList. Returns an array of media nodes, or NULL when
 * the upstream could not be reached or answered with anything unusable.
 *
 * Never throws. That is the whole point: the caller's job is to serve what it
 * already has, and an exception here would turn a degraded read into a failed
 * one. Every failure mode — 403, 5xx, timeout, socket error, malformed body,
 * GraphQL `errors` — collapses to the same null.
 *
 * Deliberately a SINGLE attempt with no retry. The current failure is a
 * deliberate shutdown on AniList's side, not a blip: retrying inside the
 * callable would just hold the client open for the timeout twice over and
 * hammer an API whose owners have asked for quiet. The next call retries
 * naturally, and by then the cache may already have been filled by someone
 * else's request.
 */
async function fetchAniListMeta(ids) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ANILIST_TIMEOUT_MS);
  try {
    const res = await fetch(ANILIST_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ query: ANILIST_META_QUERY, variables: { ids } }),
      signal: controller.signal,
    });
    if (!res.ok) {
      console.warn(`[animeMeta] AniList HTTP ${res.status} for ${ids.length} id(s)`);
      return null;
    }
    const body = await res.json();
    if (body.errors) {
      console.warn(`[animeMeta] AniList GraphQL error: ${JSON.stringify(body.errors).slice(0, 300)}`);
      return null;
    }
    const media = body?.data?.Page?.media;
    return Array.isArray(media) ? media : null;
  } catch (e) {
    // Includes AbortError from the timeout and any DNS/socket failure.
    console.warn(`[animeMeta] AniList unreachable: ${e && e.message}`);
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Resolves anime metadata for up to [ANIME_META_MAX_IDS] AniList ids, serving
 * Firestore first and filling gaps from AniList.
 *
 * Cache-first, and degrading by design. The response separates what it could
 * answer from what it could not:
 *
 *   meta        — id -> document, for everything available (fresh OR stale)
 *   unavailable — ids with no cached copy AND no successful fetch
 *   stale       — ids served from cache past the TTL because the refresh failed
 *   upstream    — 'ok' | 'skipped' | 'unreachable'
 *
 * A caller NEVER gets an exception because AniList is down. Stale data is
 * returned in preference to nothing: a two-month-old genre list is correct,
 * and genres do not move. Only genuine argument errors throw.
 *
 * No server-side rate limiter, deliberately — see the note on the export.
 */
exports.fetchAnimeMeta = onCall(
  { region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in to read anime metadata.');
    }

    const raw = request.data && request.data.anilistIds;
    if (!Array.isArray(raw) || raw.length === 0) {
      throw new HttpsError('invalid-argument', 'anilistIds must be a non-empty array.');
    }
    // Dedupe BEFORE the cap so a caller asking for the same id 60 times is
    // answered rather than refused.
    const ids = [...new Set(raw)];
    for (const id of ids) {
      if (!Number.isInteger(id) || id <= 0) {
        throw new HttpsError('invalid-argument', 'Every anilistId must be a positive integer.');
      }
    }
    if (ids.length > ANIME_META_MAX_IDS) {
      throw new HttpsError(
        'invalid-argument',
        `At most ${ANIME_META_MAX_IDS} ids per call (got ${ids.length}).`,
      );
    }

    // ── 1. Cache first ────────────────────────────────────────────────────
    const col = db.collection(ANIME_META);
    const snaps = await db.getAll(...ids.map((id) => col.doc(String(id))));

    const now = Date.now();
    const meta = {};
    const stale = [];
    const needFetch = [];

    snaps.forEach((snap, i) => {
      const id = ids[i];
      if (!snap.exists) {
        needFetch.push(id);
        return;
      }
      const data = snap.data();
      const fetchedAt = data.fetchedAt;
      const at = fetchedAt && typeof fetchedAt.toMillis === 'function' ? fetchedAt.toMillis() : 0;
      // Serialize the timestamp: a raw Firestore Timestamp crosses the
      // callable boundary as {_seconds,_nanoseconds}, which is nobody's idea
      // of a contract.
      meta[id] = { ...data, fetchedAt: at };
      if (now - at > ANIME_META_TTL_MS) {
        stale.push(id);
        needFetch.push(id);
      }
    });

    if (needFetch.length === 0) {
      return { meta, unavailable: [], stale: [], upstream: 'skipped' };
    }

    // ── 2. Fill the gaps, tolerating an upstream that is simply gone ──────
    const media = await fetchAniListMeta(needFetch);
    if (media === null) {
      // AniList unreachable. Serve what we have; say plainly what we could
      // not answer. `stale` entries are already present in `meta`.
      const unavailable = needFetch.filter((id) => meta[id] === undefined);
      return { meta, unavailable, stale, upstream: 'unreachable' };
    }

    const batch = db.batch();
    for (const m of media) {
      if (!m || !Number.isInteger(m.id)) continue;
      const body = metaFromMedia(m);
      batch.set(col.doc(String(m.id)), { ...body, fetchedAt: FieldValue.serverTimestamp() });
      // Returned with the request time rather than the pending sentinel —
      // serverTimestamp() resolves only on commit and would serialize as null.
      meta[m.id] = { ...body, fetchedAt: now };
      const wasStale = stale.indexOf(m.id);
      if (wasStale !== -1) stale.splice(wasStale, 1);
    }
    await batch.commit();

    // An id AniList simply does not know (deleted or wrong id) stays
    // unavailable rather than being cached as an empty document.
    const unavailable = needFetch.filter((id) => meta[id] === undefined);
    return { meta, unavailable, stale, upstream: 'ok' };
  },
);

// ─────────────────────────── CURRENCY ────────────────────────────────────

const CURRENCY_LEDGER = 'currency_ledger';

/// Upper bound on a single spend. Not a product rule — a blast radius, and a
/// check on the CATALOGUE rather than on the caller: the charge is read from
/// store_items, so the only way to exceed this is a mistyped price in
/// catalogue.json. It fails loudly as `internal` instead of draining a
/// balance.
const MAX_SPEND = 100000;

/// Bound on itemId so a caller cannot write an unbounded string into every
/// ledger entry.
const MAX_ITEM_ID_LENGTH = 64;

/**
 * Whether itemId can be used as a Firestore document id at all.
 *
 * This gate is new, and it is here because the catalogue moved. While the
 * table was a constant, `hasOwnProperty` rejected every unrecognised string
 * BEFORE any reference was built. Now the catalogue IS a lookup, so the
 * reference is built first — and `.doc('a/b')` throws out of the SDK, which
 * the caller receives as `internal` instead of a clean unknown-item refusal.
 *
 * It checks addressability only — slash, the two relative ids, and the
 * __reserved__ form — and deliberately does NOT impose a naming pattern, so
 * the catalogue stays free to name its rows.
 */
function addressableId(itemId) {
  return !itemId.includes('/') &&
    itemId !== '.' && itemId !== '..' &&
    !/^__.*__$/.test(itemId);
}

/// The catalogue, in Firestore. Defined by functions/tools/catalogue.json,
/// pushed by the seed script, read here and by the client.
///
/// There is no hardcoded copy any more, and deliberately no fallback to one.
/// A fallback would turn a failed or partial seed into a silent divergence —
/// the server charging one price while the catalogue says another, with
/// nothing anywhere reporting it. Every read below FAILS CLOSED instead: a
/// missing document refuses the call and says so.
const STORE_ITEMS_COLLECTION = 'store_items';
const CONFIG_COLLECTION = 'config';
const SPIN_CONFIG_DOC = 'spin_wheel';

/// Slots the server accepts. NOT catalogue data, and NOT moved to Firestore.
///
/// This is the function's input contract — "is this a slot name I handle" —
/// and the answer is decided by code, not by data: a new slot needs a branch
/// in equipCosmetic and a renderer in the client before it means anything.
/// Making it a document would advertise that a slot can be added by editing
/// data, which is the same false promise as moving the art would have been.
///
/// It has a twin in the client's CosmeticSlot, and that duplication is the
/// same class as the UTC day-id and the bio length: shared VOCABULARY that
/// each layer must enforce independently, which a catalogue cannot collapse.
///
/// A catalogue row carrying a slot outside this list cannot do harm: the
/// requested slot is checked against this list first, so a bogus stored slot
/// simply never matches and the equip refuses.
const COSMETIC_SLOTS = ['frame', 'postBorder', 'nameEffect'];

/**
 * Reads and validates one catalogue row inside a transaction.
 *
 * Throws rather than returning null, because every caller's next move on a
 * missing row is to refuse — and a stored row with a bad price is a seeding
 * fault, not a user error, so it surfaces as `internal` rather than as
 * something the caller did wrong.
 */
function catalogueItem(itemSnap, itemId) {
  if (!itemSnap.exists) {
    throw new HttpsError(
      'failed-precondition',
      'No such item.',
      { reason: 'unknown-item', itemId },
    );
  }
  const item = itemSnap.data();
  if (!Number.isInteger(item.price) || item.price <= 0) {
    throw new HttpsError('internal', `Catalogue price for ${itemId} is not a positive integer.`);
  }
  if (typeof item.sellable !== 'boolean') {
    throw new HttpsError('internal', `Catalogue sellable for ${itemId} is not a boolean.`);
  }
  return item;
}

/**
 * Deducts AniGold, grants the item, and records why — atomically.
 *
 * Three writes in one transaction: the new balance, the ledger receipt, and
 * the inventory document that IS the ownership claim. Either all of it
 * happened or none of it did.
 *
 * Items are one-time. The inventory doc is keyed by itemId, so owning
 * something twice is not representable, and the transaction refuses an
 * already-owned item before it touches the balance.
 *
 * WHAT THE CALLER NO LONGER DECIDES
 *
 * The item must exist in store_items, it must be marked sellable, and the
 * amount charged is the catalogue's price. All three were once the client's
 * to choose: any string bought an inventory document, held-back items were
 * gated in the wallet widget only, and the caller named its own price — a
 * modified client bought a 250-gold border for 1.
 *
 * `amount` is still required, as a checksum rather than an input: the caller
 * states the price it displayed, and a disagreement refuses instead of
 * silently charging the other number. See the note at that check.
 *
 * WHY A TRANSACTION, AND WHY THE LEDGER IS INSIDE IT
 *
 * A read-then-write would let two rapid calls both observe 100, both judge a
 * 60-gold purchase affordable, and both commit — 120 gold spent against a
 * 100 balance. Inside runTransaction the second attempt is retried against
 * the committed balance and refuses on the re-read.
 *
 * The balance update and the ledger entry are writes in the SAME transaction,
 * so Firestore commits both or neither. There is no window in which gold is
 * deducted without a row explaining it, and none in which a row claims a
 * deduction that did not happen. That is the whole reason the ledger write is
 * not a follow-up call: a ledger that can disagree with the balance is worse
 * than no ledger, because it would be trusted.
 *
 * NOT idempotent across retries. A client that calls twice for one tap spends
 * twice, exactly as two taps would. Making a purchase idempotent needs a
 * client-supplied key checked inside the transaction, which belongs with the
 * inventory work rather than here.
 */
exports.spendGold = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in to spend AniGold.');
  }
  const uid = request.auth.uid;

  const claimedAmount = request.data && request.data.amount;
  const itemId = request.data && request.data.itemId;

  if (typeof itemId !== 'string' || itemId.length === 0 ||
      itemId.length > MAX_ITEM_ID_LENGTH || !addressableId(itemId)) {
    throw new HttpsError(
      'invalid-argument',
      `itemId must be a non-empty string of at most ${MAX_ITEM_ID_LENGTH} characters.`,
    );
  }

  // Only SHAPE is checked out here now. Everything that depends on what the
  // item actually is happens inside the transaction, because that is where
  // the catalogue is read.
  if (!Number.isInteger(claimedAmount) || claimedAmount <= 0) {
    throw new HttpsError('invalid-argument', 'amount must be a positive integer.');
  }

  const userRef = db.collection('users').doc(uid);
  const invRef = userRef.collection('inventory').doc(itemId);
  const itemRef = db.collection(STORE_ITEMS_COLLECTION).doc(itemId);
  const entryRef = db.collection(CURRENCY_LEDGER).doc(uid).collection('entries').doc();

  return db.runTransaction(async (tx) => {
    // ── READS ────────────────────────────────────────────────────────────
    // Firestore forbids a read after the first write in a transaction, so
    // EVERY read happens here, before anything is written. getAll fetches all
    // three in one round trip and makes the ordering constraint impossible to
    // break by accident later — there is no second await further down to move.
    const [snap, invSnap, itemSnap] = await tx.getAll(userRef, invRef, itemRef);

    // The catalogue row joins the batch rather than being fetched separately:
    // three documents in the same round trip the two already cost.
    //
    // The refusal ORDER below is unchanged from when this table was a
    // constant — unknown, then not-for-sale, then price, then profile, then
    // ownership, then balance — because each step is only meaningful once the
    // one before it has passed.
    const item = catalogueItem(itemSnap, itemId);

    // Sellability is the server's call, not the shop widget's.
    if (!item.sellable) {
      throw new HttpsError(
        'failed-precondition',
        'This item is not for sale.',
        { reason: 'not-for-sale', itemId, unavailable: item.unavailable ?? null },
      );
    }

    // THE PRICE IS THE CATALOGUE'S. `amount` is the caller stating what it
    // believes the price to be — a checksum, not an input. Its job survived
    // the move to one source of truth and arguably matters more now: the
    // client reads a CACHE of the catalogue, so it can be behind, and a
    // mismatch means the user is looking at a stale price. Charging the real
    // one silently would make the UI a liar.
    if (claimedAmount !== item.price) {
      throw new HttpsError(
        'failed-precondition',
        'That price is out of date.',
        { reason: 'price-mismatch', itemId, price: item.price, offered: claimedAmount },
      );
    }

    // Read from the catalogue, never from the request. This is the line that
    // makes the price server-owned; everything above is diagnosis.
    const amount = item.price;
    if (amount > MAX_SPEND) {
      throw new HttpsError('internal', `Catalogue price for ${itemId} exceeds ${MAX_SPEND}.`);
    }

    if (!snap.exists) {
      throw new HttpsError('not-found', 'No profile for this account.');
    }

    // Ownership is checked BEFORE the balance, and refuses before anything is
    // deducted: charging for something already owned is the worse failure, so
    // it is ruled out first. Reading it inside the transaction is what makes
    // a double tap safe — the second attempt is retried against the committed
    // state, sees the doc this one wrote, and refuses rather than charging
    // twice for one item.
    if (invSnap.exists) {
      throw new HttpsError(
        'failed-precondition',
        'You already own this item.',
        { reason: 'already-owned', itemId },
      );
    }

    // Absent on profiles written before the field existed — an empty balance,
    // not an error. A stored non-number is corruption and must not be coerced
    // into free gold, so it is refused rather than defaulted.
    const raw = snap.get('aniGold');
    const before = raw === undefined ? 0 : raw;
    if (!Number.isInteger(before) || before < 0) {
      throw new HttpsError('internal', 'Stored balance is not a non-negative integer.');
    }

    if (before < amount) {
      // The one refusal the UI has to render differently from a failure:
      // nothing went wrong, the user simply cannot afford this. No other
      // branch here uses failed-precondition, and `reason` makes the match
      // exact rather than a string comparison on the message.
      throw new HttpsError(
        'failed-precondition',
        'Not enough AniGold.',
        { reason: 'insufficient-funds', balance: before, required: amount },
      );
    }

    const after = before - amount;

    // ── WRITES ───────────────────────────────────────────────────────────
    // All three commit together or none does. The grant is not a follow-up
    // call for the same reason the ledger is not: a purchase that can take
    // gold without handing over the item is worse than one that fails
    // outright, because the failure is invisible and the user has no way to
    // ask for it again — the item would already be "bought".
    //
    // Written explicitly rather than with increment(-amount): the balance the
    // ledger row claims and the balance the document ends on are then the
    // same computed number, and cannot drift.
    tx.update(userRef, { aniGold: after });
    tx.set(entryRef, {
      userId: uid,
      kind: 'spend',
      currency: 'aniGold',
      amount,
      itemId,
      balanceBefore: before,
      balanceAfter: after,
      createdAt: FieldValue.serverTimestamp(),
    });
    // Keyed by itemId, so the document IS the ownership claim — there is no
    // count to get wrong. ledgerEntryId ties the grant to the receipt that
    // paid for it, which is what makes a later audit answer "why does this
    // account own this" without guessing.
    tx.set(invRef, {
      itemId,
      source: 'purchase',
      pricePaid: amount,
      ledgerEntryId: entryRef.id,
      acquiredAt: FieldValue.serverTimestamp(),
    });

    return { balance: after, spent: amount, itemId, entryId: entryRef.id };
  });
});

// ─────────────────────────── COSMETICS ───────────────────────────────────


/**
 * Sets or clears the cosmetic displayed in one slot.
 *
 * Two checks the client cannot be trusted to make: that the caller OWNS the
 * item, and that the item belongs in the slot they asked for. The first could
 * live in security rules via exists() on the inventory doc; the second could
 * not, which is why this is a function.
 *
 * Unequipping is `itemId: null` — the slot key is deleted rather than set to a
 * sentinel, so "not in the map" is the only representation of empty and there
 * is no second one to handle.
 */
exports.equipCosmetic = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in to change your cosmetics.');
  }
  const uid = request.auth.uid;

  const slot = request.data && request.data.slot;
  // Absent and null both mean unequip; anything else must be a catalogue id.
  const itemId = request.data && request.data.itemId != null ? request.data.itemId : null;

  if (!COSMETIC_SLOTS.includes(slot)) {
    throw new HttpsError(
      'invalid-argument',
      `slot must be one of: ${COSMETIC_SLOTS.join(', ')}.`,
    );
  }

  const userRef = db.collection('users').doc(uid);
  const field = `equipped.${slot}`;

  // Unequip needs no ownership check — giving something up is always allowed,
  // and it stays allowed for an item that was later withdrawn from the
  // catalogue, which is exactly when someone most needs to take it off.
  //
  // update() on a document that does not exist fails, so a missing profile
  // was already refused — but as an unhandled error. It gets the same
  // not-found as every other path, from the failure itself: checking first
  // would cost a read and still leave the profile free to vanish in between.
  if (itemId === null) {
    try {
      await userRef.update({ [field]: FieldValue.delete() });
    } catch (e) {
      if (e.code === 5 /* NOT_FOUND */) {
        throw new HttpsError('not-found', 'No profile for this account.');
      }
      throw e;
    }
    return { slot, itemId: null };
  }

  if (typeof itemId !== 'string' || itemId.length === 0 ||
      itemId.length > MAX_ITEM_ID_LENGTH || !addressableId(itemId)) {
    throw new HttpsError('invalid-argument', 'Unknown cosmetic.');
  }

  const invRef = userRef.collection('inventory').doc(itemId);
  const itemRef = db.collection(STORE_ITEMS_COLLECTION).doc(itemId);

  return db.runTransaction(async (tx) => {
    // Read before write, same constraint as spendGold — and the catalogue row
    // rides along in the same batch.
    const [userSnap, invSnap, itemSnap] = await tx.getAll(userRef, invRef, itemRef);

    const entry = catalogueItem(itemSnap, itemId);
    // No slot at all means it is not a cosmetic (verification, streak_restore)
    // — nothing to display, so nothing to equip. Note this is NOT gated on
    // `sellable`: a withdrawn cosmetic somebody already owns stays equippable,
    // and unequip never reaches here at all.
    if (!entry.slot) {
      throw new HttpsError('invalid-argument', `${itemId} is not a cosmetic.`);
    }
    if (entry.slot !== slot) {
      throw new HttpsError(
        'invalid-argument',
        `${itemId} goes in the ${entry.slot} slot, not ${slot}.`,
      );
    }

    if (!userSnap.exists) {
      throw new HttpsError('not-found', 'No profile for this account.');
    }
    if (!invSnap.exists) {
      // Its own reason, alongside insufficient-funds and already-owned: the
      // user has to be told to buy it, not offered a retry.
      throw new HttpsError(
        'failed-precondition',
        'You do not own this item.',
        { reason: 'not-owned', itemId, slot },
      );
    }

    // A dot path so the other slots are untouched — a whole-map write here
    // would silently unequip everything else.
    tx.update(userRef, { [field]: itemId });
    return { slot, itemId };
  });
});

// ─────────────────────────── DAILY SPIN ──────────────────────────────────

const SPINS = 'spins';

// The prize table lives in config/spin_wheel, read inside the transaction
// below. The constraints it must satisfy have not changed by moving:
//
//   ORDER IS LOAD-BEARING. The index drawn here is what the client rotates
//   to, so reordering the stored array silently re-points every wedge.
//
//   THE DRAW IS UNIFORM, and the wheel is painted with equal wedges, so the
//   picture and the odds agree. Weighting a big prize down to a sliver of its
//   drawn size would make the face a lie; tuning payouts means resizing the
//   wedges too.
//
//   Expected value is the mean of the array — 31.875 for the seeded eight.

/**
 * One free spin per UTC day. The server decides the outcome.
 *
 * This is the only earn path that can be honest today. Every other one —
 * quiz scores, episodes watched, posts reacted to — would have the server
 * paying out on a claim the client made about itself, with nothing recorded
 * anywhere to check it against. A spin needs nothing from the caller except
 * the request, so there is no claim to verify.
 *
 * WHERE "ALREADY SPUN" LIVES
 *
 * spins/{uid}_{YYYY-MM-DD}, a deterministic id, which makes the record
 * SELF-DEDUPLICATING: a second spin on the same day is the same document, so
 * "have they spun" is one point read and "spin twice" is not representable.
 * Read inside the transaction, so two taps racing cannot both draw.
 *
 * Note this is NOT the shape upload_grants uses, and deliberately: its cap is
 * three per day, and a key that encodes only the day cannot hold three of
 * anything — it has to count. A deterministic key works here precisely
 * because the allowance is exactly one.
 */
exports.spinWheel = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in to spin.');
  }
  const uid = request.auth.uid;

  // The SERVER's clock decides the day. A client-supplied date would let a
  // caller claim yesterday and spin again.
  const now = new Date();
  const day = utcDayId(now);
  const nextSpinAt = nextUtcMidnight(now);

  const userRef = db.collection('users').doc(uid);
  const spinRef = db.collection(SPINS).doc(`${uid}_${day}`);
  const configRef = db.collection(CONFIG_COLLECTION).doc(SPIN_CONFIG_DOC);
  const entryRef = db.collection(CURRENCY_LEDGER).doc(uid).collection('entries').doc();

  return db.runTransaction(async (tx) => {
    // ── READS ────────────────────────────────────────────────────────────
    const [userSnap, spinSnap, configSnap] = await tx.getAll(userRef, spinRef, configRef);

    // The prize table is ONE document because its order is load-bearing: the
    // segment returned below is an index into it, and rows read partially or
    // out of order would land the wheel on a different wedge than was paid.
    // Fails closed — no hardcoded array to fall back to.
    if (!configSnap.exists) {
      throw new HttpsError(
        'failed-precondition',
        'The prize wheel is not configured.',
        { reason: 'catalogue-missing', doc: `${CONFIG_COLLECTION}/${SPIN_CONFIG_DOC}` },
      );
    }
    const prizes = configSnap.get('prizes');
    if (!Array.isArray(prizes) || prizes.length === 0 ||
        !prizes.every((p) => Number.isInteger(p) && p > 0)) {
      throw new HttpsError('internal', 'Stored prize table is not a non-empty array of positive integers.');
    }

    if (!userSnap.exists) {
      throw new HttpsError('not-found', 'No profile for this account.');
    }
    if (spinSnap.exists) {
      throw new HttpsError(
        'failed-precondition',
        'You have already spun today.',
        {
          reason: 'already-spun',
          nextSpinAt: nextSpinAt.toISOString(),
          // What they won last time, so the UI can say so rather than just
          // refusing.
          prize: spinSnap.get('prize') ?? null,
        },
      );
    }

    const raw = userSnap.get('aniGold');
    const before = raw === undefined ? 0 : raw;
    if (!Number.isInteger(before) || before < 0) {
      throw new HttpsError('internal', 'Stored balance is not a non-negative integer.');
    }

    // randomInt, not Math.random: this decides money. It draws from the OS
    // CSPRNG and is uniform over the range with no modulo bias, which a
    // `Math.floor(Math.random() * n)` is only accidentally.
    const segment = randomInt(0, prizes.length);
    const prize = prizes[segment];
    const after = before + prize;

    // ── WRITES ───────────────────────────────────────────────────────────
    // One transaction, same reasoning as spendGold: a credit without a
    // receipt breaks the property that the ledger explains the balance, and
    // a spin record written separately could be lost, handing out a second
    // free spin.
    tx.update(userRef, { aniGold: after });
    tx.set(entryRef, {
      userId: uid,
      kind: 'earn',
      source: 'daily_spin',
      currency: 'aniGold',
      amount: prize,
      balanceBefore: before,
      balanceAfter: after,
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(spinRef, {
      userId: uid,
      day,
      segment,
      prize,
      ledgerEntryId: entryRef.id,
      createdAt: FieldValue.serverTimestamp(),
    });

    // segment drives the animation; prize is what was actually credited. Both
    // are returned so the dialog can state the real number even if the
    // client's painted wheel face has drifted from this table.
    return { segment, prize, balance: after, nextSpinAt: nextSpinAt.toISOString() };
  });
});

// ─────────────────────────── DAILY TASKS ───────────────────────────────────

const TASK_CLAIMS = 'task_claims';
const DAILY_TASKS_DOC = 'daily_tasks';

/// Blast radius for a single task reward, the MAX_SPEND of earning: the
/// reward is read from the catalogue, so the only way past this is a
/// mistyped number in catalogue.json, and that fails as `internal` instead
/// of minting it.
const MAX_TASK_REWARD = 1000;

/// How many of today's likes one claim examines. A claim needs only
/// `target` good ones, but the first few may be on the claimer's own posts or
/// on posts since deleted, so it looks a little further than `target`. Past
/// this the claim reports what it counted rather than scanning a heavy
/// liker's whole day inside a transaction.
const REACTION_SCAN_LIMIT = 50;

/**
 * Tasks the server can VERIFY, by id — code, not catalogue data, for the
 * same reason COSMETIC_SLOTS is: a task means nothing until something here
 * can prove it was done. The catalogue says what a task PAYS and how much is
 * needed; this says whether one exists at all. A catalogue row with no
 * verifier is refused as unknown, never paid on trust.
 *
 * Watching, True Fan and sharing are absent on purpose. Watching and True
 * Fan need server-run sessions before anything can be proven; sharing has no
 * signal the server ever sees.
 */
const TASK_VERIFIERS = {
  reactions: verifyReactions,
};

/**
 * React to N posts: distinct posts, still existing, not the claimer's own,
 * liked during the current UTC day.
 *
 * WHY A COLLECTION-GROUP QUERY. A like lives under the post it likes, so
 * "everything one user liked today" crosses every post. The alternative is a
 * per-user mirror written beside each like — a second copy of the fact that
 * can disagree with the first. This reads the likes themselves.
 *
 * DISTINCT is structural. A like is posts/{postId}/likes/{uid}: one document
 * per (post, liker), so N documents are N posts, and unliking and re-liking
 * the same post is still one.
 *
 * TODAY is the document's createTime, not likedAt. likedAt finds candidates
 * through the index, but it has only been pinned to request.time since the
 * rule that shipped with this function; a like written before then could
 * carry any date, including a future one planted in advance. createTime is
 * set by Firestore and nobody can write it.
 *
 * VIDEO LIKES share the collection name. Honest clients never put `uid` on
 * them, but the video like rule accepts any body, so the path is checked
 * rather than trusted: only a like whose parent is a top-level posts
 * document counts.
 *
 * Every read happens here, before the caller writes anything — the
 * transaction's read-before-write constraint.
 */
async function verifyReactions(tx, uid, dayStart, dayEnd) {
  const likes = await tx.get(
    db.collectionGroup('likes')
      .where('uid', '==', uid)
      .where('likedAt', '>=', Timestamp.fromDate(dayStart))
      .where('likedAt', '<', Timestamp.fromDate(dayEnd))
      .limit(REACTION_SCAN_LIMIT),
  );
  const candidates = likes.docs.filter((d) => {
    const post = d.ref.parent.parent;
    const created = d.createTime.toDate();
    return d.id === uid
      && post !== null
      && post.parent.id === 'posts'
      && post.parent.parent === null
      && created >= dayStart
      && created < dayEnd;
  });
  const posts = candidates.length === 0
    ? []
    : await tx.getAll(...candidates.map((d) => d.ref.parent.parent));

  const counted = [];
  const own = [];
  const deleted = [];
  for (const post of posts) {
    // Self-likes are excluded HERE rather than refused by the like rule. The
    // post is read anyway to confirm it still exists, so knowing its author
    // costs nothing; refusing in the rule would break liking your own post
    // for every build already installed.
    if (!post.exists) deleted.push(post.id);
    else if (post.get('userId') === uid) own.push(post.id);
    else counted.push(post.id);
  }
  return { counted, own, deleted };
}

/**
 * Pays a daily task, once per UTC day, after proving it was done.
 *
 * CLAIMED BY TAP, NOT CREDITED BY TRIGGER. The proof runs once, at the moment
 * the user asks, inside the same transaction that credits — so there is no
 * window between "counted" and "paid", and nothing runs on the likes of
 * people who never open the wallet.
 *
 * ONCE PER DAY is the spin's device: the claim record's id is
 * {uid}_{day}_{taskId}, so a second claim is the same document and is
 * refused. A deterministic id works because the allowance is exactly one.
 *
 * The reward and the target come from config/daily_tasks, seeded from
 * catalogue.json like the prize wheel, and fail closed when missing.
 */
exports.claimDailyTask = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in to claim a task.');
  }
  const uid = request.auth.uid;

  const taskId = request.data && request.data.taskId;
  if (typeof taskId !== 'string' || !Object.prototype.hasOwnProperty.call(TASK_VERIFIERS, taskId)) {
    throw new HttpsError('invalid-argument', 'No such task.', { reason: 'unknown-task', taskId: taskId ?? null });
  }
  const verify = TASK_VERIFIERS[taskId];

  // The server's clock decides the day, as for the spin.
  const now = new Date();
  const day = utcDayId(now);
  const dayStart = startOfUtcDay(now);
  const dayEnd = nextUtcMidnight(now);

  const userRef = db.collection('users').doc(uid);
  const claimRef = db.collection(TASK_CLAIMS).doc(`${uid}_${day}_${taskId}`);
  const configRef = db.collection(CONFIG_COLLECTION).doc(DAILY_TASKS_DOC);
  const entryRef = db.collection(CURRENCY_LEDGER).doc(uid).collection('entries').doc();

  return db.runTransaction(async (tx) => {
    // ── READS ────────────────────────────────────────────────────────────
    const [userSnap, claimSnap, configSnap] = await tx.getAll(userRef, claimRef, configRef);

    if (!configSnap.exists) {
      throw new HttpsError(
        'failed-precondition',
        'Daily tasks are not configured.',
        { reason: 'catalogue-missing', doc: `${CONFIG_COLLECTION}/${DAILY_TASKS_DOC}` },
      );
    }
    const task = configSnap.get(taskId);
    if (task === undefined) {
      throw new HttpsError('failed-precondition', 'That task is not offered.', { reason: 'not-offered', taskId });
    }
    if (!task || !Number.isInteger(task.reward) || task.reward <= 0 || task.reward > MAX_TASK_REWARD ||
        !Number.isInteger(task.target) || task.target <= 0 || task.target > REACTION_SCAN_LIMIT) {
      throw new HttpsError('internal', `Stored daily task ${taskId} is malformed.`);
    }

    if (!userSnap.exists) {
      throw new HttpsError('not-found', 'No profile for this account.');
    }
    // Before the proof, not after: a second claim should cost two reads, not
    // a scan.
    if (claimSnap.exists) {
      throw new HttpsError(
        'failed-precondition',
        'Already claimed today.',
        { reason: 'already-claimed', nextClaimAt: dayEnd.toISOString(), reward: claimSnap.get('reward') ?? null },
      );
    }

    const { counted, own, deleted } = await verify(tx, uid, dayStart, dayEnd);
    if (counted.length < task.target) {
      // Says WHY, because the bar the user was looking at cannot know about
      // a post deleted since, and a modified client's self-likes are counted
      // there too.
      throw new HttpsError(
        'failed-precondition',
        'Not done yet.',
        {
          reason: 'not-complete',
          counted: counted.length,
          target: task.target,
          ownPosts: own.length,
          deletedPosts: deleted.length,
        },
      );
    }

    const raw = userSnap.get('aniGold');
    const before = raw === undefined ? 0 : raw;
    if (!Number.isInteger(before) || before < 0) {
      throw new HttpsError('internal', 'Stored balance is not a non-negative integer.');
    }
    const after = before + task.reward;

    // ── WRITES ───────────────────────────────────────────────────────────
    tx.update(userRef, { aniGold: after });
    tx.set(entryRef, {
      userId: uid,
      kind: 'earn',
      source: `daily_task_${taskId}`,
      currency: 'aniGold',
      amount: task.reward,
      balanceBefore: before,
      balanceAfter: after,
      createdAt: FieldValue.serverTimestamp(),
    });
    // create, not set: if the record appeared since it was read, the
    // transaction retries and the read above refuses — a second payout is
    // not representable either way.
    tx.create(claimRef, {
      userId: uid,
      day,
      taskId,
      reward: task.reward,
      target: task.target,
      // The evidence: which posts were counted.
      posts: counted,
      ledgerEntryId: entryRef.id,
      createdAt: FieldValue.serverTimestamp(),
    });

    return { taskId, reward: task.reward, balance: after, nextClaimAt: dayEnd.toISOString() };
  });
});

// ─────────────────────────── ACCOUNT DELETION ──────────────────────────────

const ACCOUNT_DELETIONS = 'account_deletions';
const USERNAMES = 'usernames';

/**
 * The deletion job's phases, in order — the vocabulary of `phase` on the job
 * document, and exactly what the callable and the worker write.
 *
 *   created      0a  the job exists — the COMMIT POINT. Everything after it is
 *                    retried until done; nothing before it has happened.
 *   accepted     0b–0e done: handles tombstoned, Auth disabled and revoked,
 *                    profile document deleted.
 *   r2 · dmImages · dmMessages · followEdges · marks · content · records ·
 *   counters · profileTree
 *                    the worker's steps 1–9, run twice: pass 1 at once, pass 2
 *                    after sweepWait.
 *   sweepWait    waits until revokedAt + 65 minutes, when the last ID token
 *                    issued before revocation has expired.
 *   final        step 10: tombstone any handle claimed in the window, delete
 *                    the Auth user, delete this job. There is no `done` phase —
 *                    a finished job no longer exists.
 */
const DELETION_PHASES = [
  'created', 'accepted',
  'r2', 'dmImages', 'dmMessages', 'followEdges', 'marks', 'content',
  'records', 'counters', 'profileTree', 'sweepWait', 'final',
];

/**
 * Turns every handle [uid] holds or has retired into a tombstone.
 *
 * A tombstone is { retiredAt } and nothing else. With no uid and no
 * retiredBy, no rule path can claim it, reclaim it or delete it: a create on
 * an existing document is an update, the update rule needs one of those two
 * fields to name the caller, and handles are never deleted. So it is
 * unclaimable forever without any rule that mentions tombstones.
 *
 * Queried, not read off the profile: the profile may already be gone on a
 * retry, and a handle claimed in the last moments would not be on it anyway.
 */
async function tombstoneHandles(uid) {
  const registry = db.collection(USERNAMES);
  const [active, retired] = await Promise.all([
    registry.where('uid', '==', uid).get(),
    registry.where('retiredBy', '==', uid).get(),
  ]);
  const now = FieldValue.serverTimestamp();
  const docs = [
    ...active.docs.map((d) => [d.ref, { retiredAt: now }]),
    // A handle retired earlier keeps the moment it was retired.
    ...retired.docs.map((d) => [d.ref, { retiredAt: d.get('retiredAt') ?? now }]),
  ];
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    for (const [ref, data] of docs.slice(i, i + 400)) batch.set(ref, data);
    await batch.commit();
  }
  return docs.map(([ref]) => ref.id);
}

/**
 * Disables the Auth user and revokes its refresh tokens.
 *
 * Disabling stops any new sign-in and any token refresh; revoking ends the
 * sessions already out there. Neither ends the ID token a client already
 * holds — that stays valid until it expires, up to an hour — which is what
 * the users-create guard and the worker's final sweep are for.
 *
 * An Auth user that is already gone is success: a retry after a previous
 * attempt deleted it has nothing left to lock.
 */
async function lockAuth(uid) {
  const auth = getAuth();
  try {
    await auth.updateUser(uid, { disabled: true });
    await auth.revokeRefreshTokens(uid);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }
}

/**
 * Steps 0b–0e: tombstone the handles, lock the Auth user, delete the profile
 * document. Shared by the callable and by the worker, which begins by
 * finishing any job the callable left at `created`.
 *
 * Every step is idempotent. A failure is recorded on the job, not thrown, and
 * leaves the phase at `created` so the next attempt repeats the steps.
 * Returns whether all of them succeeded.
 */
async function acceptJob(uid, jobRef) {
  const failures = [];
  const step = async (name, fn) => {
    try {
      return await fn();
    } catch (e) {
      failures.push(`${name}: ${e.message}`);
      return undefined;
    }
  };

  // 0b and 0c are independent; 0e follows both. (0d is firestore.rules.)
  const [handles, locked] = await Promise.all([
    step('handles', () => tombstoneHandles(uid)),
    step('auth', async () => { await lockAuth(uid); return true; }),
  ]);
  // Only the document. Its subcollections — the follow graph among them —
  // are the index the worker's later steps read from.
  await step('profile', () => db.collection('users').doc(uid).delete());

  const complete = failures.length === 0;
  await jobRef.update({
    phase: complete ? 'accepted' : 'created',
    ...(handles && handles.length ? { handles: FieldValue.arrayUnion(...handles) } : {}),
    ...(locked ? { revokedAt: FieldValue.serverTimestamp() } : {}),
    attempts: FieldValue.increment(1),
    lastError: complete ? null : failures.join('; '),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return complete;
}

/**
 * Starts deleting the caller's account. Steps 0a–0e of the order, and only
 * those — the account is made unreachable here; the bulk of the deletion is
 * the worker's.
 *
 * 0a IS THE COMMIT POINT. If creating the job fails, nothing has happened and
 * the caller is told so. Once the job exists the deletion is committed: every
 * later step is idempotent, a failure is recorded on the job rather than
 * thrown, and the phase stays `created` so the step is finished by a retry —
 * the caller's own within the hour its ID token still verifies, or the
 * worker's, which begins by completing any job still at `created`. The caller
 * is told the request was accepted either way, because either way the account
 * is going: after 0c it cannot be used, whatever else failed.
 *
 * `confirm: 'DELETE'` is required so no stray call — a mis-wired button, a
 * replayed request body — can start this.
 *
 * Then it enqueues the worker (processAccountDeletion), which does the rest.
 */
exports.deleteAccount = onCall({ region: 'europe-west1' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Sign in to delete an account.');
  }
  if (!request.data || request.data.confirm !== 'DELETE') {
    throw new HttpsError('invalid-argument', 'Deletion must be confirmed.', { reason: 'unconfirmed' });
  }
  const uid = request.auth.uid;
  const jobRef = db.collection(ACCOUNT_DELETIONS).doc(uid);

  // ── 0a ─────────────────────────────────────────────────────────────────
  // The job, and with it the users-create guard in firestore.rules, which
  // refuses to re-create this profile for as long as the job exists.
  try {
    await jobRef.create({
      uid,
      phase: 'created',
      // The worker's resume point inside its current phase. Opaque to
      // everything but the worker.
      cursor: null,
      requestedAt: FieldValue.serverTimestamp(),
      // Set when 0c succeeds. The final sweep waits an hour past this, so
      // an ID token issued before the revocation has expired.
      revokedAt: null,
      handles: [],
      anonymous: request.auth.token.firebase?.sign_in_provider === 'anonymous',
      attempts: 0,
      lastError: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    if (e.code !== 6 /* ALREADY_EXISTS */) {
      throw new HttpsError('internal', 'Could not start the deletion. Nothing was changed.');
    }
    // A repeat call. Past `created` the pre-steps are done and the worker
    // owns the job — running them again could only move it backwards.
    const job = await jobRef.get();
    if (job.get('phase') !== 'created') {
      return { status: 'accepted', complete: true, phase: job.get('phase') };
    }
  }

  // ── 0b–0e ──────────────────────────────────────────────────────────────
  const complete = await acceptJob(uid, jobRef);

  // Hand the rest to the worker. Failing to enqueue is not failing to
  // delete: the job exists, and the daily sweep re-enqueues any job that
  // stops moving.
  try {
    await enqueueDeletion(uid);
  } catch (e) {
    await jobRef.update({ lastError: `enqueue: ${e.message}` }).catch(() => {});
  }

  return { status: 'accepted', complete, phase: complete ? 'accepted' : 'created' };
});

// ─────────────────────── ACCOUNT DELETION — THE WORKER ─────────────────────
//
// Steps 1–10 of the order, as a Cloud Tasks job that saves its phase and a
// cursor after every page, re-enqueues itself before its time runs out, and
// can be killed at any instant and resumed by the next task.
//
//   pass 1: r2 → dmImages → dmMessages → followEdges → marks → content →
//           records → counters → profileTree → sweepWait
//   pass 2: the same nine phases again, once the revoked token has expired
//           (revokedAt + 65 min), to catch whatever it wrote in that hour
//   final:  tombstone any handle claimed in the window, delete the Auth user,
//           delete the job
//
// Every phase is idempotent: deletes of absent documents succeed, recording an
// affected parent merges, counters are applied as increment(actual − stored).
// What is NOT naturally safe is two tasks running one job at once, which a
// lease on the job document prevents.

const DELETION_WORKER = 'processAccountDeletion';
const DELETION_QUEUE = `locations/europe-west1/functions/${DELETION_WORKER}`;
const WORKER_TIMEOUT_SECONDS = 540;
const PASS_PHASES = DELETION_PHASES.slice(
  DELETION_PHASES.indexOf('r2'), DELETION_PHASES.indexOf('profileTree') + 1);

// A job is stalled when nothing has touched it for this long. Healthy jobs
// write updatedAt after every page; a failing one writes it on every retry.
const STALL_AFTER_MS = 6 * 60 * 60 * 1000;
// Re-enqueues by the daily sweep before a job is declared stuck.
const MAX_STALLS = 3;

// Overridable in the EMULATOR ONLY, so a test can walk the whole job in
// seconds. In production these are fixed: nothing can shorten the sweep's
// wait or point R2 somewhere else.
const EMULATED = process.env.FUNCTIONS_EMULATOR === 'true';
const emulatorInt = (name, fallback) => {
  const v = EMULATED ? Number(process.env[name]) : NaN;
  return Number.isInteger(v) && v > 0 ? v : fallback;
};
// 60 minutes: an ID token issued the moment before revocation lasts an hour
// and cannot be refreshed. 5 more: clock skew and requests already in flight.
const SWEEP_DELAY_SECONDS = emulatorInt('DELETION_SWEEP_DELAY_SECONDS', 65 * 60);
// Seven of the nine minutes; the rest is for saving the cursor and enqueueing.
const WORKER_BUDGET_MS = emulatorInt('DELETION_BUDGET_MS', 420 * 1000);
const PAGE = emulatorInt('DELETION_PAGE', 300);
const LEASE_MS = (WORKER_TIMEOUT_SECONDS + 60) * 1000;

const affectedRef = (uid, parentPath) => db.collection(ACCOUNT_DELETIONS).doc(uid)
  .collection('affected').doc(parentPath.replace(/\//g, '|'));

/** A DM header preview, exactly as the client writes one (dm_service.dart). */
function dmPreview(message) {
  const text = (message.get('text') || '').trim();
  if (text) {
    let end = Math.min(text.length, 120);
    if (end < text.length && (text.charCodeAt(end - 1) & 0xFC00) === 0xD800) end--;
    return text.slice(0, end);
  }
  return message.get('imageUrl') ? '📷 Photo' : '';
}

function r2Client() {
  const override = EMULATED ? process.env.R2_ENDPOINT_OVERRIDE : '';
  return new S3Client({
    region: 'auto',
    endpoint: override || `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    forcePathStyle: Boolean(override),
    requestChecksumCalculation: 'WHEN_REQUIRED',
    credentials: {
      accessKeyId: R2_ACCESS_KEY_ID.value(),
      secretAccessKey: R2_SECRET_ACCESS_KEY.value(),
    },
  });
}

// The Admin SDK's Cloud Tasks client authenticates every request, the
// emulator's included, though the emulator ignores the token. An emulator run
// may have no credential to mint one with — this repo's are sealed from
// credentials on purpose — so in the EMULATOR ONLY the queue is reached
// through a second app whose credential returns a placeholder. Production
// uses the default app. A second app, not the default one, because Firestore
// on the default app refuses any credential but a real one.
let emulatorTasksApp = null;
function deletionQueue() {
  if (!EMULATED) return getFunctions().taskQueue(DELETION_QUEUE);
  emulatorTasksApp = emulatorTasksApp || initializeApp({
    projectId: process.env.GCLOUD_PROJECT,
    credential: { getAccessToken: async () => ({ access_token: 'emulator', expires_in: 3600 }) },
  }, 'emulator-tasks');
  return getFunctions(emulatorTasksApp).taskQueue(DELETION_QUEUE);
}

async function enqueueDeletion(uid, delaySeconds = 0) {
  await deletionQueue().enqueue({ uid }, delaySeconds > 0 ? { scheduleDelaySeconds: delaySeconds } : {});
}

/** Commits [ops] (functions of a batch) in batches the size of a page. */
async function inBatches(items, apply) {
  for (let i = 0; i < items.length; i += 400) {
    const batch = db.batch();
    for (const item of items.slice(i, i + 400)) apply(batch, item);
    await batch.commit();
  }
}

// ── The phases ─────────────────────────────────────────────────────────────
// Each takes ctx = { uid, cursor, save(cursor), spent() } and returns true when
// the phase is complete, false when it ran out of time. It saves its cursor
// after every page, so the next task resumes from that page, not from zero.
//
// The budget is checked AFTER each page, never before the first: every task
// makes progress. Checked first, a page slower than the budget — or a budget
// already spent by the time the lease is taken — would re-enqueue a task that
// did nothing, forever.

/**
 * 1 · R2. Listed by prefix, not through deleteVideoObjects: that refuses
 * without the video's Firestore document and never sees an upload that was
 * abandoned before its document existed. The listing shrinks as it deletes,
 * so resuming is re-listing; the cursor only counts.
 */
async function phaseR2(ctx) {
  const s3 = r2Client();
  const prefix = `ani_videos/${ctx.uid}/`;
  let deleted = (ctx.cursor && ctx.cursor.deleted) || 0;
  for (;;) {
    const page = await s3.send(new ListObjectsV2Command({
      Bucket: R2_BUCKET, Prefix: prefix, MaxKeys: Math.min(PAGE, 1000),
    }));
    const keys = (page.Contents || []).map((o) => o.Key);
    if (keys.length === 0) return true;
    // One DeleteObject per key, the call deleteVideoObjects already proves
    // against R2, rather than DeleteObjects and its checksum requirements.
    for (let i = 0; i < keys.length; i += 20) {
      await Promise.all(keys.slice(i, i + 20).map((Key) =>
        s3.send(new DeleteObjectCommand({ Bucket: R2_BUCKET, Key }))));
    }
    deleted += keys.length;
    await ctx.save({ deleted });
    if (ctx.spent()) return false;
  }
}

/** The next conversation [uid] is in, after [afterCid]. */
async function nextConversation(uid, afterCid) {
  let q = db.collection('conversations').where('participants', 'array-contains', uid)
    .orderBy(FieldPath.documentId()).limit(1);
  if (afterCid) q = q.startAfter(afterCid);
  const snap = await q.get();
  return snap.empty ? null : snap.docs[0];
}

/**
 * 2 · DM images, found through their message docs — the only record of who
 * sent which image. This MUST precede phase 3: once those messages are gone,
 * nothing says which files in the conversation's folder are theirs, and no
 * client may delete a DM image at all.
 *
 * Cursor { after, cid, mid }: the last conversation finished, and the
 * position inside the one in progress.
 */
async function phaseDmImages(ctx) {
  const bucket = getStorage().bucket();
  let { after = null, cid = null, mid = null } = ctx.cursor || {};
  for (;;) {
    const conv = cid ? db.collection('conversations').doc(cid) : (await nextConversation(ctx.uid, after))?.ref;
    if (!conv) return true;
    cid = conv.id;
    let q = conv.collection('messages').where('senderId', '==', ctx.uid)
      .orderBy(FieldPath.documentId()).limit(PAGE);
    if (mid) q = q.startAfter(mid);
    const page = await q.get();
    await Promise.all(page.docs.filter((m) => m.get('imageUrl')).map((m) =>
      bucket.file(`dm_images/${cid}/${m.id}.jpg`).delete({ ignoreNotFound: true })));
    if (page.size < PAGE) {
      after = cid; cid = null; mid = null;
    } else {
      mid = page.docs[page.size - 1].id;
    }
    await ctx.save({ after, cid, mid });
    if (ctx.spent()) return false;
  }
}

/**
 * One conversation's side of phase 3. Returns false if time ran out part-way;
 * every step shrinks what the next attempt finds, so re-running it is safe.
 */
async function scrubConversation(convSnap, uid, spent) {
  const conv = convSnap.ref;
  const msgs = conv.collection('messages');
  const other = (convSnap.get('participants') || []).find((p) => p !== uid) || null;

  // Both sides gone: nothing is left for anyone, so the whole conversation
  // goes — the other side's messages and images with it.
  const otherGone = other && (
    (convSnap.get('deletedParticipants') || []).includes(other) ||
    (await db.collection(ACCOUNT_DELETIONS).doc(other).get()).exists);
  if (otherGone) {
    await db.recursiveDelete(conv);
    await getStorage().bucket().deleteFiles({ prefix: `dm_images/${conv.id}/` });
    return true;
  }

  for (;;) {
    const mine = await msgs.where('senderId', '==', uid).limit(PAGE).get();
    if (mine.empty) break;
    await inBatches(mine.docs, (b, d) => b.delete(d.ref));
    if (spent()) return false;
  }
  const reactionKey = new FieldPath('reactions', uid);
  for (;;) {
    const reacted = await msgs.where(reactionKey, '>=', '').limit(PAGE).get();
    if (reacted.empty) break;
    await inBatches(reacted.docs, (b, d) => b.update(d.ref, reactionKey, FieldValue.delete()));
    if (spent()) return false;
  }

  // The header, in a transaction with the newest message left, so a message
  // the survivor sends meanwhile is not overwritten by an older preview.
  // blockedBy gains the deleted uid: the existing message rule refuses any
  // new message while blockedBy is non-empty, and only a participant can
  // remove their own uid from it — so the conversation is closed for good
  // with no rule change. deletedParticipants is what lets the app say
  // "Deleted account" rather than a blank name.
  await db.runTransaction(async (tx) => {
    const latest = await tx.get(msgs.orderBy('createdAt', 'desc').limit(1));
    const last = latest.docs[0];
    tx.update(conv, {
      lastMessage: last ? dmPreview(last) : '',
      lastSenderId: last ? last.get('senderId') : '',
      [`lastReadAt.${uid}`]: FieldValue.delete(),
      blockedBy: FieldValue.arrayUnion(uid),
      deletedParticipants: FieldValue.arrayUnion(uid),
    });
  });
  return true;
}

/** 3 · DM messages, reactions and headers. Cursor { after }: the last finished. */
async function phaseDmMessages(ctx) {
  let after = (ctx.cursor && ctx.cursor.after) || null;
  for (;;) {
    const conv = await nextConversation(ctx.uid, after);
    if (!conv) return true;
    if (!(await scrubConversation(conv, ctx.uid, ctx.spent))) return false;
    after = conv.id;
    await ctx.save({ after });
    if (ctx.spent()) return false;
  }
}

/**
 * 4 · Follow edges in OTHER people's documents: users/{them}/followers/{uid}
 * and users/{them}/following/{uid}. Their own following/ and followers/ lists
 * are the only index of those edges, which is why this precedes phase 9. Each
 * edge's owner is recorded for phase 8 in the same batch that deletes it.
 *
 * Cursor { list, after }: which list, and the last edge done in it.
 */
async function phaseFollowEdges(ctx) {
  let { list = 'following', after = null } = ctx.cursor || {};
  const lists = {
    // I follow them → their followers/ holds me, their followerCount counts me.
    following: { mirror: 'followers', field: 'followerCount' },
    // They follow me → their following/ holds me, their followingCount counts me.
    followers: { mirror: 'following', field: 'followingCount' },
  };
  for (;;) {
    let q = db.collection('users').doc(ctx.uid).collection(list).orderBy(FieldPath.documentId()).limit(PAGE);
    if (after) q = q.startAfter(after);
    const page = await q.get();
    const { mirror, field } = lists[list];
    await inBatches(page.docs, (b, d) => {
      const them = db.collection('users').doc(d.id);
      b.set(affectedRef(ctx.uid, them.path),
        { path: them.path, counts: { [field]: { sub: mirror } } }, { merge: true });
      b.delete(them.collection(mirror).doc(ctx.uid));
    });
    if (page.size < PAGE) {
      if (list === 'followers') return true;
      list = 'followers'; after = null;
    } else {
      after = page.docs[page.size - 1].id;
    }
    await ctx.save({ list, after });
    if (ctx.spent()) return false;
  }
}

/**
 * 5 · Their marks in other people's spaces: likes, comments, votes, story
 * views, room memberships. Each counted parent is recorded in the same batch
 * that deletes the mark — the marks are the only record of which counters to
 * fix.
 *
 * Cursor { part, after }: the kind in progress, and the last document path
 * done. The owner is checked against the document id, not just the field.
 */
async function phaseMarks(ctx) {
  const uid = ctx.uid;
  const parts = ['likes', 'comments', 'votes', 'viewers', 'members'];
  let { part = 'likes', after = null } = ctx.cursor || {};
  const next = async () => {
    const i = parts.indexOf(part);
    if (i === parts.length - 1) return true;
    part = parts[i + 1]; after = null;
    await ctx.save({ part, after });
    return false;
  };

  for (;;) {
    let q;
    if (part === 'likes') q = db.collectionGroup('likes').where('uid', '==', uid);
    else if (part === 'comments') q = db.collectionGroup('comments').where('userId', '==', uid);
    else if (part === 'votes') q = db.collectionGroup('votes').where('userId', '==', uid);
    else if (part === 'members') q = db.collectionGroup('members').where('uid', '==', uid);
    // Story views carry no owner field; the id is the viewer. Stories are
    // short-lived, so this scan stays small once expired stories are cleaned.
    else q = db.collectionGroup('viewers');
    q = q.orderBy(FieldPath.documentId()).limit(PAGE);
    if (after) q = q.startAfter(after);
    const page = await q.get();

    await inBatches(page.docs, (b, d) => {
      const parent = d.ref.parent.parent;
      if (part === 'likes' && d.id === uid && parent) {
        b.set(affectedRef(uid, parent.path), { path: parent.path, counts: { likes: { sub: 'likes' } } }, { merge: true });
        b.delete(d.ref);
      } else if (part === 'comments' && parent) {
        b.set(affectedRef(uid, parent.path),
          { path: parent.path, counts: { commentsCount: { sub: 'comments' } } }, { merge: true });
        b.delete(d.ref);
      } else if (part === 'votes' && d.id.startsWith(`${uid}_`)) {
        const day = d.get('dayId') || d.ref.parent.parent.id;
        const anime = d.get('anilist_id');
        if (Number.isInteger(anime)) {
          const tally = `community_votes/${day}/tally/${anime}`;
          b.set(affectedRef(uid, tally), {
            path: tally,
            counts: { voteCount: { collection: `community_votes/${day}/votes`, field: 'anilist_id', value: anime } },
          }, { merge: true });
        }
        b.delete(d.ref);
      } else if ((part === 'members' || part === 'viewers') && d.id === uid) {
        // Member counts fix themselves: the room trigger recomputes.
        b.delete(d.ref);
      }
    });

    if (page.size < PAGE) {
      if (await next()) return true;
    } else {
      after = page.docs[page.size - 1].ref.path;
      await ctx.save({ part, after });
    }
    if (ctx.spent()) return false;
  }
}

/**
 * 6 · Their own content, recursively — with everything beneath it, other
 * people's likes and comments included — then the Storage prefixes. The
 * public leaderboard entries go first: they carry a copy of the name.
 * Cursor { part }; every query shrinks as it deletes.
 */
async function phaseContent(ctx) {
  const uid = ctx.uid;
  const parts = [
    ['trueFan', () => db.collection('trueFanScores').where('userId', '==', uid)],
    ['posts', () => db.collection('posts').where('userId', '==', uid)],
    ['videos', () => db.collection('ani_videos').where('userId', '==', uid)],
    ['stories', () => db.collection('stories').where('uid', '==', uid)],
    ['rooms', () => db.collection('rooms').where('hostUid', '==', uid)],
  ];
  let part = (ctx.cursor && ctx.cursor.part) || 'trueFan';
  for (let i = parts.findIndex(([name]) => name === part); i >= 0 && i < parts.length; i++) {
    part = parts[i][0];
    for (;;) {
      const page = await parts[i][1]().limit(20).get();
      if (page.empty) break;
      for (const d of page.docs) await db.recursiveDelete(d.ref);
      await ctx.save({ part });
      if (ctx.spent()) return false;
    }
  }
  const bucket = getStorage().bucket();
  for (const prefix of ['posts', 'post_images', 'stories', 'ani_videos']) {
    await bucket.deleteFiles({ prefix: `${prefix}/${uid}/` });
  }
  return true;
}

/**
 * 7 · Private records. Reports they FILED keep the report and lose
 * reporterId: a victim deleting their account must not erase the report
 * against the person they reported. Cursor { part }; each query shrinks.
 */
async function phaseRecords(ctx) {
  const uid = ctx.uid;
  const idRange = (collection) => db.collection(collection).orderBy(FieldPath.documentId())
    .startAt(`${uid}_`).endAt(`${uid}_`);
  const parts = ['reports', 'ledger', 'spins', 'taskClaims', 'grants'];
  let part = (ctx.cursor && ctx.cursor.part) || 'reports';
  for (let i = parts.indexOf(part); i >= 0 && i < parts.length; i++) {
    part = parts[i];
    if (part === 'ledger') {
      await db.recursiveDelete(db.collection(CURRENCY_LEDGER).doc(uid));
      await ctx.save({ part });
      continue;
    }
    for (;;) {
      const q = part === 'reports' ? db.collection('reports').where('reporterId', '==', uid)
        : part === 'spins' ? idRange(SPINS)
          : part === 'taskClaims' ? idRange(TASK_CLAIMS)
            : db.collection(GRANTS).where('uid', '==', uid);
      const page = await q.limit(PAGE).get();
      if (page.empty) break;
      await inBatches(page.docs, (b, d) => (part === 'reports'
        ? b.update(d.ref, { reporterId: FieldValue.delete() })
        : b.delete(d.ref)));
      await ctx.save({ part });
      if (ctx.spent()) return false;
    }
  }
  return true;
}

/**
 * 8 · Recompute every recorded counter, as increment(actual − stored), in a
 * transaction per parent: a second run computes zero, and a like landing
 * meanwhile conflicts on the parent and retries rather than being lost.
 * Cursor { after }: the last affected record done.
 */
async function phaseCounters(ctx) {
  let after = (ctx.cursor && ctx.cursor.after) || null;
  const records = db.collection(ACCOUNT_DELETIONS).doc(ctx.uid).collection('affected');
  for (;;) {
    let q = records.orderBy(FieldPath.documentId()).limit(PAGE);
    if (after) q = q.startAfter(after);
    const page = await q.get();
    for (const rec of page.docs) {
      const { path, counts } = rec.data();
      const parent = db.doc(path);
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(parent);
        if (!snap.exists) return;
        const updates = {};
        for (const [field, spec] of Object.entries(counts || {})) {
          const source = spec.sub ? parent.collection(spec.sub)
            : db.collection(spec.collection).where(spec.field, '==', spec.value);
          const actual = (await tx.get(source.count())).data().count;
          const stored = Number.isInteger(snap.get(field)) ? snap.get(field) : 0;
          if (actual !== stored) updates[field] = FieldValue.increment(actual - stored);
        }
        if (Object.keys(updates).length) tx.update(parent, updates);
      });
    }
    if (page.size < PAGE) return true;
    after = page.docs[page.size - 1].id;
    await ctx.save({ after });
    if (ctx.spent()) return false;
  }
}

/** 9 · users/{uid} and everything left beneath it. */
async function phaseProfileTree(ctx) {
  await db.recursiveDelete(db.collection('users').doc(ctx.uid));
  return true;
}

const PHASE_RUNNERS = {
  r2: phaseR2, dmImages: phaseDmImages, dmMessages: phaseDmMessages, followEdges: phaseFollowEdges,
  marks: phaseMarks, content: phaseContent, records: phaseRecords, counters: phaseCounters,
  profileTree: phaseProfileTree,
};

/**
 * Takes the job's lease, or returns why not: null when the job no longer
 * exists (finished), false when another task holds it. The lease outlives
 * the function's timeout, so a crashed holder's lease expires on its own.
 */
async function acquireLease(jobRef, holder) {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(jobRef);
    if (!snap.exists) return null;
    const until = snap.get('leaseUntil');
    if (until && until.toMillis() > Date.now() && snap.get('leaseHolder') !== holder) return false;
    tx.update(jobRef, {
      leaseHolder: holder,
      leaseUntil: Timestamp.fromMillis(Date.now() + LEASE_MS),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return snap.data();
  });
}

/**
 * One task's worth of the job. Returns what the handler should do next:
 * 'requeue' (with a delay for the sweep's wait), 'done', 'gone' or 'leased'.
 */
async function runDeletion(uid) {
  const deadline = Date.now() + WORKER_BUDGET_MS;
  const spent = () => Date.now() >= deadline;
  const jobRef = db.collection(ACCOUNT_DELETIONS).doc(uid);
  const holder = randomUUID();
  const job = await acquireLease(jobRef, holder);
  if (job === null) return { outcome: 'gone' };
  if (job === false) return { outcome: 'leased' };

  let finished = false;
  let { phase, cursor = null, pass = 1 } = job;
  const log = (event, extra = {}) =>
    console.log(JSON.stringify({ event, uid, phase, pass, ...extra }));
  const save = async (next) => {
    cursor = next;
    await jobRef.update({ cursor: next, updatedAt: FieldValue.serverTimestamp() });
    log('deletion-progress', { cursor: next });
  };
  const advance = async (next) => {
    phase = next; cursor = null;
    await jobRef.update({ phase, cursor: null, pass, updatedAt: FieldValue.serverTimestamp() });
    log('deletion-phase');
  };

  try {
    for (;;) {
      if (phase === 'created') {
        // The callable left it partway. Finish its steps before anything else.
        if (!(await acceptJob(uid, jobRef))) throw new Error('pre-steps (0b–0e) still incomplete');
        phase = 'accepted';
        continue;
      }
      if (phase === 'accepted') { await advance('r2'); continue; }

      const i = PASS_PHASES.indexOf(phase);
      if (i >= 0) {
        const done = await PHASE_RUNNERS[phase]({ uid, cursor, save, spent });
        if (!done) return { outcome: 'requeue' };
        if (i < PASS_PHASES.length - 1) await advance(PASS_PHASES[i + 1]);
        else await advance(pass === 1 ? 'sweepWait' : 'final');
        if (spent()) return { outcome: 'requeue' };
        continue;
      }

      if (phase === 'sweepWait') {
        const revokedAt = (await jobRef.get()).get('revokedAt');
        if (!revokedAt) throw new Error('sweepWait without revokedAt');
        const wait = Math.ceil((revokedAt.toMillis() + SWEEP_DELAY_SECONDS * 1000 - Date.now()) / 1000);
        if (wait > 0) return { outcome: 'requeue', delaySeconds: wait };
        pass = 2;
        await advance('r2');
        continue;
      }

      if (phase === 'final') {
        // A handle claimed with the still-valid token, then the Auth user,
        // then the job with its affected/ records. Each step repeats safely.
        await tombstoneHandles(uid);
        try {
          await getAuth().deleteUser(uid);
        } catch (e) {
          if (e.code !== 'auth/user-not-found') throw e;
        }
        await db.recursiveDelete(jobRef);
        finished = true;
        log('deletion-complete');
        return { outcome: 'done' };
      }

      throw new Error(`unknown phase ${phase}`);
    }
  } finally {
    // Released BEFORE the handler enqueues the next task, or that task would
    // find the lease held and give up.
    if (!finished) {
      await jobRef.update({ leaseHolder: null, leaseUntil: null }).catch(() => {});
    }
  }
}

/**
 * The worker. One task runs the job for up to its budget, saves, and
 * enqueues the next.
 *
 * FAILURE: an error is recorded on the job (lastError, failures) and
 * rethrown, so Cloud Tasks retries the same task with backoff — the retry
 * resumes from the saved cursor. Lease contention is rethrown too, without
 * being recorded: a task that finds another holding the job retries until
 * that lease is released or expires, so a crashed holder cannot strand it.
 * After maxAttempts Cloud Tasks drops the task; the job then stops updating
 * and the daily sweep takes over.
 */
exports.processAccountDeletion = onTaskDispatched(
  {
    region: 'europe-west1',
    timeoutSeconds: WORKER_TIMEOUT_SECONDS,
    memory: '512MiB',
    secrets: [R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY],
    // 1, 2, 4, 8, 16 minutes, then hourly: about six hours of attempts.
    retryConfig: { maxAttempts: 10, minBackoffSeconds: 60, maxBackoffSeconds: 3600, maxDoublings: 4 },
    // Deletion is rare and heavy; a handful at once bounds the load a burst
    // of requests can put on Firestore and R2.
    rateLimits: { maxConcurrentDispatches: 5, maxDispatchesPerSecond: 1 },
  },
  async (req) => {
    const uid = req.data && req.data.uid;
    if (typeof uid !== 'string' || uid.length === 0 || uid.includes('/')) {
      console.error(JSON.stringify({ severity: 'ERROR', event: 'deletion-bad-task', data: req.data }));
      return; // unretryable; acknowledging it is the only useful answer
    }
    const jobRef = db.collection(ACCOUNT_DELETIONS).doc(uid);
    let result;
    try {
      result = await runDeletion(uid);
    } catch (e) {
      await jobRef.update({
        lastError: `${e.message}`.slice(0, 500),
        failures: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }).catch(() => {});
      console.error(JSON.stringify({ severity: 'ERROR', event: 'deletion-failed', uid, error: e.message }));
      throw e;
    }
    if (result.outcome === 'leased') throw new Error(`deletion ${uid}: lease held by another task`);
    if (result.outcome === 'requeue') await enqueueDeletion(uid, result.delaySeconds || 0);
  },
);

/**
 * The daily sweep: re-enqueues any job that has stopped moving, and makes a
 * job that cannot finish impossible to miss.
 *
 * Stalled = updatedAt older than six hours. A healthy job touches it after
 * every page and a failing one on every retry, so six quiet hours means
 * nothing is working on it — its task was lost, or Cloud Tasks gave up.
 * A job waiting out the sweep delay is not stalled.
 *
 * After MAX_STALLS re-enqueues the job is marked `stuck` and stays stuck:
 * it is left for a person, and logged at ERROR on every sweep until someone
 * looks — a log-based alert on event "deletion-stuck" turns that into a page.
 */
exports.sweepAccountDeletions = onSchedule(
  { schedule: 'every 24 hours', timeZone: 'Etc/UTC', region: 'europe-west1' },
  async () => {
    const cutoff = Timestamp.fromMillis(Date.now() - STALL_AFTER_MS);
    const stale = await db.collection(ACCOUNT_DELETIONS).where('updatedAt', '<', cutoff).get();
    for (const doc of stale.docs) {
      const job = doc.data();
      if (job.status === 'stuck') {
        console.error(JSON.stringify({
          severity: 'ERROR', event: 'deletion-stuck', uid: doc.id,
          phase: job.phase, lastError: job.lastError || null, failures: job.failures || 0,
        }));
        continue;
      }
      if (job.phase === 'sweepWait' && job.revokedAt &&
          job.revokedAt.toMillis() + SWEEP_DELAY_SECONDS * 1000 > Date.now()) continue;

      const stalls = (job.stalls || 0) + 1;
      if (stalls > MAX_STALLS) {
        await doc.ref.update({ status: 'stuck', stuckAt: FieldValue.serverTimestamp() });
        console.error(JSON.stringify({
          severity: 'ERROR', event: 'deletion-stuck', uid: doc.id,
          phase: job.phase, lastError: job.lastError || null, failures: job.failures || 0,
        }));
        continue;
      }
      await doc.ref.update({ stalls, updatedAt: FieldValue.serverTimestamp() });
      await enqueueDeletion(doc.id);
      console.warn(JSON.stringify({ severity: 'WARNING', event: 'deletion-requeued', uid: doc.id, phase: job.phase, stalls }));
    }
  },
);
