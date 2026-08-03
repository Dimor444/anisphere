/**
 * DM security-rules contract (Phase 1), against the Firestore emulator.
 *
 * Exercises the conversations/{cid} block the way real clients will:
 * per-user auth contexts, serverTimestamp() sentinels (the rules pin
 * createdAt/updatedAt to request.time), and the exact queries DmService
 * runs. Tests run in an isolated demo project namespace, so they never
 * touch app data living under the real project id.
 *
 * Run with the firestore emulator up:
 *   node test/dm_rules.test.js
 */

process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';

const assert = require('node:assert');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, addDoc, collection, getDocs,
  query, where, orderBy, serverTimestamp,
} = require('firebase/firestore');

const [HOST, PORT] = process.env.FIRESTORE_EMULATOR_HOST.split(':');

const A = 'userA';
const B = 'userB';
const C = 'userC';
// Mirrors DmConversation.cidFor: sorted uids joined with '_'.
const CID = [A, B].sort().join('_');

/** The exact payload DmConversation.toMap() produces. */
const createPayload = (a, b) => ({
  participants: [a, b].sort(),
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  lastMessage: '',
  lastSenderId: '',
  lastReadAt: {},
  blockedBy: [],
});

const messagePayload = (sender, text) => ({
  senderId: sender,
  text,
  createdAt: serverTimestamp(),
});

async function run(name, fn) {
  await fn();
  console.log(`  ok — ${name}`);
}

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-dm-rules',
    firestore: {
      host: HOST,
      port: Number(PORT),
      rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8'),
    },
  });
  const db = (uid) => env.authenticatedContext(uid).firestore();
  const convoRef = (d) => doc(d, 'conversations', CID);
  const messagesCol = (d) => collection(d, 'conversations', CID, 'messages');

  await env.clearFirestore();

  await run('1. userA opens a conversation with userB → one doc, correct cid', async () => {
    await assertSucceeds(setDoc(convoRef(db(A)), createPayload(A, B)));
    const snap = await getDoc(convoRef(db(A)));
    assert.strictEqual(snap.exists(), true, 'doc must exist');
    assert.strictEqual(snap.id, 'userA_userB', 'cid must be the sorted uid pair');
    assert.deepStrictEqual(snap.get('participants'), ['userA', 'userB']);
  });

  await run('2. openConversation called twice → still one doc', async () => {
    // The service path: existence check finds the doc and skips the write.
    // The rules back it up: a second blind create is a set-on-existing —
    // an update touching createdAt — which no update branch admits.
    await assertFails(setDoc(convoRef(db(A)), createPayload(A, B)));
    // watchConversations' exact query shape, run as userA:
    const mine = await getDocs(query(
      collection(db(A), 'conversations'),
      where('participants', 'array-contains', A),
      orderBy('updatedAt', 'desc'),
    ));
    assert.strictEqual(mine.docs.length, 1, 'still exactly one conversation');
  });

  await run('3. userC cannot read that conversation (permission-denied)', async () => {
    await assertFails(getDoc(convoRef(db(C))));
  });

  await run('4. userC cannot write a message into it', async () => {
    // Both participants can (baseline proving the create path works)…
    await assertSucceeds(addDoc(messagesCol(db(A)), messagePayload(A, 'hi B!')));
    await assertSucceeds(addDoc(messagesCol(db(B)), messagePayload(B, 'yo!')));
    // …and the sender must be the caller, so C fails as themselves AND
    // when trying to spoof a participant's senderId.
    await assertFails(addDoc(messagesCol(db(C)), messagePayload(C, 'let me in')));
    await assertFails(addDoc(messagesCol(db(C)), messagePayload(A, 'spoofed sender')));
  });

  await run('5. userA cannot modify lastReadAt.{userB}', async () => {
    await assertFails(updateDoc(convoRef(db(A)), { 'lastReadAt.userB': serverTimestamp() }));
    // Own key is fine — markRead()'s exact write shape.
    await assertSucceeds(updateDoc(convoRef(db(A)), { 'lastReadAt.userA': serverTimestamp() }));
  });

  await run('6. userA cannot set blockedBy to contain userB\'s uid', async () => {
    await assertFails(updateDoc(convoRef(db(A)), { blockedBy: [B] }));
    await assertFails(updateDoc(convoRef(db(A)), { blockedBy: [A, B] }));
  });

  await run('7. after blockedBy=[userA], message create is denied for BOTH', async () => {
    // Blocking yourself in is the one legal transition…
    await assertSucceeds(updateDoc(convoRef(db(A)), { blockedBy: [A] }));
    // …and a non-empty blockedBy freezes sends for both sides.
    await assertFails(addDoc(messagesCol(db(A)), messagePayload(A, 'blocked but trying')));
    await assertFails(addDoc(messagesCol(db(B)), messagePayload(B, 'other side trying')));
    // Only the blocker can lift it (B cannot remove A's entry)…
    await assertFails(updateDoc(convoRef(db(B)), { blockedBy: [] }));
    await assertSucceeds(updateDoc(convoRef(db(A)), { blockedBy: [] }));
    // …after which sends flow again.
    await assertSucceeds(addDoc(messagesCol(db(B)), messagePayload(B, 'back online')));
  });

  await env.cleanup();
  console.log('\nAll DM rules tests passed.');
  process.exit(0);
})().catch((e) => {
  console.error('\nFAILED:', e.message);
  process.exit(1);
});
