/**
 * AniSphere Cloud Functions.
 *
 * Home for writes the client is not trusted to make. Security rules deny
 * direct client writes to counters like rooms/{roomId}.memberCount, so the
 * only thing that moves them is a trigger in here.
 */

const { onDocumentCreated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

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
