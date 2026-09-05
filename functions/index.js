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
const { defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { S3Client, PutObjectCommand, DeleteObjectCommand } = require('@aws-sdk/client-s3');
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
 */
async function syncMemberCount(roomId) {
  const roomRef = db.collection('rooms').doc(roomId);
  await db.runTransaction(async (tx) => {
    const room = await tx.get(roomRef);
    if (!room.exists) return;

    const members = await tx.get(roomRef.collection('members').count());
    const actual = members.data().count;

    // Skip the write when already correct — most redeliveries land here.
    if (room.get('memberCount') === actual) return;
    tx.update(roomRef, { memberCount: actual });
  });
}

exports.onRoomMemberJoined = onDocumentCreated('rooms/{roomId}/members/{uid}', (event) =>
  syncMemberCount(event.params.roomId),
);

exports.onRoomMemberLeft = onDocumentDeleted('rooms/{roomId}/members/{uid}', (event) =>
  syncMemberCount(event.params.roomId),
);

// Exported for test/member_count.test.js: redelivery of a single event is the
// case this design exists for, and no amount of driving Firestore reproduces
// it on demand. Calling the body directly does.
exports._syncMemberCount = syncMemberCount;

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
