/**
 * DM Phase 4 contract, against the Firestore emulator: the reactions
 * update branch (the ONE mutation a message doc allows) and the
 * user/message report shapes.
 *
 * The reaction branch is the first crack in message immutability, so it is
 * probed adversarially: foreign keys, smuggled text/senderId edits, oversized
 * emoji, blocked threads, and messages written before the field existed.
 *
 * Run with the firestore emulator up:
 *   node test/dm_rules_phase4.test.js
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
  query, where, deleteField, serverTimestamp,
} = require('firebase/firestore');

const [HOST, PORT] = process.env.FIRESTORE_EMULATOR_HOST.split(':');

const A = 'userA';
const B = 'userB';
const CID = [A, B].sort().join('_');

const createPayload = () => ({
  participants: [A, B].sort(),
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  lastMessage: '',
  lastSenderId: '',
  lastReadAt: {},
  blockedBy: [],
});

async function run(name, fn) {
  await fn();
  console.log(`  ok — ${name}`);
}

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-dm-rules-p4',
    firestore: {
      host: HOST,
      port: Number(PORT),
      rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8'),
    },
  });
  const db = (uid) => env.authenticatedContext(uid).firestore();
  const convoRef = (d) => doc(d, 'conversations', CID);
  const messagesCol = (d) => collection(d, 'conversations', CID, 'messages');
  const msgRef = (d, id) => doc(d, 'conversations', CID, 'messages', id);

  await env.clearFirestore();
  await assertSucceeds(setDoc(convoRef(db(A)), createPayload()));

  // A message from A, written the normal way (no reactions field).
  const mid = 'msg_one';
  await assertSucceeds(setDoc(msgRef(db(A), mid), {
    senderId: A, text: 'reactable', createdAt: serverTimestamp(),
  }));

  await run('1. reaction add / change / remove, own key only', async () => {
    // Add (proves 5 too: this doc has NO reactions field yet).
    await assertSucceeds(updateDoc(msgRef(db(B), mid), { 'reactions.userB': '🔥' }));
    assert.strictEqual((await getDoc(msgRef(db(B), mid))).get('reactions.userB'), '🔥');
    // Change.
    await assertSucceeds(updateDoc(msgRef(db(B), mid), { 'reactions.userB': '❤️' }));
    assert.strictEqual((await getDoc(msgRef(db(B), mid))).get('reactions.userB'), '❤️');
    // Remove.
    await assertSucceeds(updateDoc(msgRef(db(B), mid), { 'reactions.userB': deleteField() }));
    assert.strictEqual((await getDoc(msgRef(db(B), mid))).get('reactions.userB'), undefined);
    // Both participants may hold their own reaction simultaneously.
    await assertSucceeds(updateDoc(msgRef(db(B), mid), { 'reactions.userB': '😂' }));
    await assertSucceeds(updateDoc(msgRef(db(A), mid), { 'reactions.userA': '👍' }));
    const both = (await getDoc(msgRef(db(A), mid))).get('reactions');
    assert.deepStrictEqual(both, { userA: '👍', userB: '😂' });
  });

  await run('2. userA cannot write a reaction under userB\'s key', async () => {
    await assertFails(updateDoc(msgRef(db(A), mid), { 'reactions.userB': '💀' }));
    // …nor clear someone else's.
    await assertFails(updateDoc(msgRef(db(A), mid), { 'reactions.userB': deleteField() }));
    // …nor rewrite the whole map to smuggle a foreign key in.
    await assertFails(updateDoc(msgRef(db(A), mid), {
      reactions: { userA: '👍', userB: '💀' },
    }));
    // An oversized "emoji" is not a reaction.
    await assertFails(updateDoc(msgRef(db(A), mid), {
      'reactions.userA': 'this is far too long to be an emoji',
    }));
    // Non-participants are refused outright.
    await assertFails(updateDoc(msgRef(db('userC'), mid), { 'reactions.userC': '🔥' }));
  });

  await run('3. reaction branch cannot smuggle a text or senderId edit', async () => {
    await assertFails(updateDoc(msgRef(db(A), mid), {
      'reactions.userA': '🔥', text: 'edited after the fact',
    }));
    await assertFails(updateDoc(msgRef(db(A), mid), {
      'reactions.userA': '🔥', senderId: B,
    }));
    await assertFails(updateDoc(msgRef(db(A), mid), {
      'reactions.userA': '🔥', imageUrl: 'https://evil.example/x.jpg',
    }));
    await assertFails(updateDoc(msgRef(db(A), mid), {
      'reactions.userA': '🔥', createdAt: serverTimestamp(),
    }));
    // Plain edits remain impossible — immutability is intact outside reactions.
    await assertFails(updateDoc(msgRef(db(A), mid), { text: 'edited' }));
    // The stored message is byte-for-byte what was written.
    const after = await getDoc(msgRef(db(A), mid));
    assert.strictEqual(after.get('text'), 'reactable');
    assert.strictEqual(after.get('senderId'), A);
  });

  await run('4. reactions rejected in a blocked conversation', async () => {
    await assertSucceeds(updateDoc(convoRef(db(A)), { blockedBy: [A] }));
    await assertFails(updateDoc(msgRef(db(A), mid), { 'reactions.userA': '😢' }));
    await assertFails(updateDoc(msgRef(db(B), mid), { 'reactions.userB': '😢' }));
    // Removing an existing reaction is equally frozen.
    await assertFails(updateDoc(msgRef(db(B), mid), { 'reactions.userB': deleteField() }));
    await assertSucceeds(updateDoc(convoRef(db(A)), { blockedBy: [] }));
    await assertSucceeds(updateDoc(msgRef(db(B), mid), { 'reactions.userB': '😢' }));
  });

  await run('5. pre-existing message (no reactions field) accepts a first one', async () => {
    // A doc written before reactions existed at all.
    const legacy = 'msg_legacy';
    await assertSucceeds(setDoc(msgRef(db(A), legacy), {
      senderId: A, text: 'from before reactions', createdAt: serverTimestamp(),
    }));
    const before = await getDoc(msgRef(db(A), legacy));
    assert.strictEqual(before.get('reactions'), undefined, 'precondition: no reactions field');
    // get('reactions', {}) is what makes this work.
    await assertSucceeds(updateDoc(msgRef(db(B), legacy), { 'reactions.userB': '👍' }));
    assert.deepStrictEqual((await getDoc(msgRef(db(B), legacy))).get('reactions'), { userB: '👍' });
  });

  await run('7a. Block List must query on participants, never blockedBy alone', async () => {
    await assertSucceeds(updateDoc(convoRef(db(A)), { blockedBy: [A] }));
    // The shape the Block List actually uses: the inbox query, filtered
    // client-side. Allowed, because it matches what the read rule gates on.
    const viaParticipants = await getDocs(query(
      collection(db(A), 'conversations'),
      where('participants', 'array-contains', A),
    ));
    assert.strictEqual(
      viaParticipants.docs.filter((d) => (d.get('blockedBy') || []).includes(A)).length,
      1, 'the blocked thread is reachable through the participants query');
    // The tempting server-side filter is REJECTED — rules are not filters,
    // so Firestore cannot prove a blockedBy-only query returns only docs
    // the caller may read. This is why the service filters client-side.
    await assertFails(getDocs(query(
      collection(db(A), 'conversations'),
      where('blockedBy', 'array-contains', A),
    )));
    await assertSucceeds(updateDoc(convoRef(db(A)), { blockedBy: [] }));
  });

  await run('8. user report and message report both land in reports/ (no rules change)', async () => {
    // The USER-shaped report — a new shape in an existing collection whose
    // create rule has NO hasOnly whitelist, so no rules change is needed.
    // This asserts that rather than assuming it.
    await assertSucceeds(addDoc(collection(db(A), 'reports'), {
      reportedUid: B, cid: CID, reason: 'abuse', reporterId: A, createdAt: serverTimestamp(),
    }));
    // The message-shaped report: same sink plus messageId.
    await assertSucceeds(addDoc(collection(db(A), 'reports'), {
      reportedUid: B, cid: CID, messageId: mid, reason: 'spam',
      reporterId: A, createdAt: serverTimestamp(),
    }));
    // reporterId is still pinned to the caller…
    await assertFails(addDoc(collection(db(A), 'reports'), {
      reportedUid: B, cid: CID, reason: 'abuse', reporterId: B, createdAt: serverTimestamp(),
    }));
    // …and the sink stays write-only: nobody reads reports back.
    await assertFails(getDocs(collection(db(A), 'reports')));

    // Confirm both docs actually landed, via an admin (rules-bypassing) view.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const all = await getDocs(collection(ctx.firestore(), 'reports'));
      const mine = all.docs.map((d) => d.data()).filter((r) => r.reporterId === A);
      assert.strictEqual(mine.length, 2, 'both reports stored');
      const userReport = mine.find((r) => r.messageId === undefined);
      const msgReport = mine.find((r) => r.messageId !== undefined);
      assert.deepStrictEqual(
        Object.keys(userReport).sort(),
        ['cid', 'createdAt', 'reason', 'reportedUid', 'reporterId'],
        'user report shape');
      assert.strictEqual(msgReport.messageId, mid);
      assert.strictEqual(msgReport.reportedUid, B);
    });
  });

  await env.cleanup();
  console.log('\nAll Phase 4 DM tests passed.');
  process.exit(0);
})().catch((e) => {
  console.error('\nFAILED:', e.message);
  process.exit(1);
});
