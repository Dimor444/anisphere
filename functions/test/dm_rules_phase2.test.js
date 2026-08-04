/**
 * DM Phase 2 contract, against the Firestore emulator: the send pipeline
 * (message + parent preview in one batch, exactly DmService.sendMessage's
 * shape), the hardened rules (preview cap, server-stamped updatedAt,
 * no-empty-message), pagination, and read marks.
 *
 * Run with the firestore emulator up:
 *   node test/dm_rules_phase2.test.js
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
  doc, getDoc, setDoc, updateDoc, collection, getDocs, getCountFromServer,
  query, where, orderBy, limit, startAfter, serverTimestamp, writeBatch,
  Timestamp,
} = require('firebase/firestore');

const [HOST, PORT] = process.env.FIRESTORE_EMULATOR_HOST.split(':');

const A = 'userA';
const B = 'userB';
const C = 'userC';
const CID = [A, B].sort().join('_');
const PAGE = 30; // DmService.messagesPageSize

const createPayload = (a, b) => ({
  participants: [a, b].sort(),
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  lastMessage: '',
  lastSenderId: '',
  lastReadAt: {},
  blockedBy: [],
});

/** DmService.sendMessage's exact write shape: one batch, message + preview. */
function sendBatch(db, cid, sender, text) {
  const batch = writeBatch(db);
  batch.set(doc(collection(db, 'conversations', cid, 'messages')), {
    senderId: sender,
    text,
    createdAt: serverTimestamp(),
  });
  batch.update(doc(db, 'conversations', cid), {
    lastMessage: text.slice(0, 120),
    lastSenderId: sender,
    updatedAt: serverTimestamp(),
  });
  return batch.commit();
}

async function run(name, fn) {
  await fn();
  console.log(`  ok — ${name}`);
}

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-dm-rules-p2',
    firestore: {
      host: HOST,
      port: Number(PORT),
      rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8'),
    },
  });
  const db = (uid) => env.authenticatedContext(uid).firestore();
  const convoRef = (d, cid = CID) => doc(d, 'conversations', cid);
  const messagesCol = (d, cid = CID) => collection(d, 'conversations', cid, 'messages');

  await env.clearFirestore();
  await assertSucceeds(setDoc(convoRef(db(A)), createPayload(A, B)));

  await run('1. two users exchange messages both directions (batched send pipeline)', async () => {
    await assertSucceeds(sendBatch(db(A), CID, A, 'hi B!'));
    await assertSucceeds(sendBatch(db(B), CID, B, 'yo!'));
  });

  await run('2. lastMessage / updatedAt / list ordering update correctly', async () => {
    const after = await getDoc(convoRef(db(A)));
    assert.strictEqual(after.get('lastMessage'), 'yo!');
    assert.strictEqual(after.get('lastSenderId'), B);
    assert.ok(after.get('updatedAt').toMillis() > after.get('createdAt').toMillis(),
      'updatedAt must have advanced past createdAt');

    // A second thread bumped later must sort first in the inbox query.
    const cidAC = [A, C].sort().join('_');
    await assertSucceeds(setDoc(convoRef(db(A), cidAC), createPayload(A, C)));
    await assertSucceeds(sendBatch(db(A), cidAC, A, 'newest thread'));
    const inbox = await getDocs(query(
      collection(db(A), 'conversations'),
      where('participants', 'array-contains', A),
      orderBy('updatedAt', 'desc'),
    ));
    assert.deepStrictEqual(inbox.docs.map((d) => d.id), [cidAC, CID],
      'most recently bumped thread must lead the list');
  });

  await run('3. rules reject lastMessage > 120 chars', async () => {
    await assertFails(updateDoc(convoRef(db(A)), {
      lastMessage: 'x'.repeat(121),
      lastSenderId: A,
      updatedAt: serverTimestamp(),
    }));
    // …and a forged (non-server) updatedAt is rejected too.
    await assertFails(updateDoc(convoRef(db(A)), {
      lastMessage: 'ok',
      lastSenderId: A,
      updatedAt: Timestamp.fromMillis(Date.now() - 60_000),
    }));
  });

  await run('4. rules reject empty text with no imageUrl', async () => {
    await assertFails(setDoc(doc(messagesCol(db(A))), {
      senderId: A, text: '', createdAt: serverTimestamp(),
    }));
    // Empty text WITH an image is a legal Phase 3 shape.
    await assertSucceeds(setDoc(doc(messagesCol(db(A))), {
      senderId: A, text: '', imageUrl: 'https://example.com/x.jpg', createdAt: serverTimestamp(),
    }));
  });

  await run('5. rules reject a message whose senderId != auth.uid', async () => {
    await assertFails(setDoc(doc(messagesCol(db(B))), {
      senderId: A, text: 'spoofed', createdAt: serverTimestamp(),
    }));
  });

  await run('6. blocked conversation: send denied for BOTH sides', async () => {
    await assertSucceeds(updateDoc(convoRef(db(A)), { blockedBy: [A] }));
    await assertFails(sendBatch(db(A), CID, A, 'blocker trying'));
    await assertFails(sendBatch(db(B), CID, B, 'other side trying'));
    await assertFails(setDoc(doc(messagesCol(db(B))), {
      senderId: B, text: 'bare create', createdAt: serverTimestamp(),
    }));
    // Blocker lifts it; traffic resumes.
    await assertSucceeds(updateDoc(convoRef(db(A)), { blockedBy: [] }));
    await assertSucceeds(sendBatch(db(B), CID, B, 'back online'));
  });

  await run('7. pagination: 80 seeded messages page 30 / 30 / rest, no dupes, descending', async () => {
    for (let i = 0; i < 80; i++) {
      const sender = i % 2 === 0 ? A : B;
      await setDoc(doc(messagesCol(db(sender))), {
        senderId: sender, text: `seed #${i}`, createdAt: serverTimestamp(),
      });
    }
    // 84 total now: 2 (test 1) + 1 image-only (test 4) + 1 (test 6) + 80.
    const newestFirst = query(messagesCol(db(A)), orderBy('createdAt', 'desc'));
    const sizes = [];
    const ids = new Set();
    let prevMillis = Infinity;
    let cursor = null;
    for (;;) {
      const page = await getDocs(cursor === null
        ? query(newestFirst, limit(PAGE))
        : query(newestFirst, startAfter(cursor), limit(PAGE)));
      if (page.docs.length === 0) break;
      sizes.push(page.docs.length);
      for (const d of page.docs) {
        assert.ok(!ids.has(d.id), 'no message may appear in two pages');
        ids.add(d.id);
        const ms = d.get('createdAt').toMillis();
        assert.ok(ms <= prevMillis, 'strictly newest-first across page boundaries');
        prevMillis = ms;
      }
      cursor = page.docs[page.docs.length - 1];
      if (page.docs.length < PAGE) break;
    }
    assert.deepStrictEqual(sizes, [30, 30, 24], '84 messages must page as 30/30/24');
  });

  await run('8. markRead zeroes the unread count behind the list dot', async () => {
    // DmService.unreadCount's exact query, before the mark: no read
    // timestamp yet, so every message from the other side counts.
    const before = await getCountFromServer(query(
      messagesCol(db(A)), where('senderId', '!=', A),
    ));
    assert.strictEqual(before.data().count, 42, "B's 42 messages start unread");

    await assertSucceeds(updateDoc(convoRef(db(A)), { 'lastReadAt.userA': serverTimestamp() }));

    const mark = (await getDoc(convoRef(db(A)))).get('lastReadAt.userA');
    const after = await getCountFromServer(query(
      messagesCol(db(A)),
      where('senderId', '!=', A),
      where('createdAt', '>', mark),
    ));
    assert.strictEqual(after.data().count, 0, 'nothing newer than the fresh mark');
  });

  await env.cleanup();
  console.log('\nAll Phase 2 DM tests passed.');
  process.exit(0);
})().catch((e) => {
  console.error('\nFAILED:', e.message);
  process.exit(1);
});
