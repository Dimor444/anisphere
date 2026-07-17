/**
 * AniSphere Cloud Functions.
 *
 * Home for writes the client is not trusted to make. Security rules deny
 * direct client writes to counters like rooms/{roomId}.memberCount, so the
 * only thing that moves them is a trigger in here.
 */

const { onDocumentCreated, onDocumentDeleted } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp();

const db = getFirestore();

/**
 * Shifts rooms/{roomId}.memberCount by [delta], flooring at 0.
 *
 * A transaction rather than FieldValue.increment because the floor needs to
 * read the current value: a decrement that raced ahead of its create (or ran
 * twice — triggers are at-least-once) must not push the count negative.
 * A room deleted out from under its members is a no-op, not an error.
 */
async function shiftMemberCount(roomId, delta) {
  const roomRef = db.collection('rooms').doc(roomId);
  await db.runTransaction(async (tx) => {
    const room = await tx.get(roomRef);
    if (!room.exists) return;
    const current = room.get('memberCount');
    const next = Math.max(0, (typeof current === 'number' ? current : 0) + delta);
    tx.update(roomRef, { memberCount: next });
  });
}

exports.onRoomMemberJoined = onDocumentCreated('rooms/{roomId}/members/{uid}', (event) =>
  shiftMemberCount(event.params.roomId, 1),
);

exports.onRoomMemberLeft = onDocumentDeleted('rooms/{roomId}/members/{uid}', (event) =>
  shiftMemberCount(event.params.roomId, -1),
);
