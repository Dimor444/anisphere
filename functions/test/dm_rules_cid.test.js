/**
 * cid-binding contract for conversations/{cid}, against the Firestore
 * emulator.
 *
 * The hole this closes: validConversationCreate used to check only that
 * the caller was one of two participants — it never tied the document id
 * to those participants. Anyone could therefore create
 * conversations/{A_B} with participants [attacker, X] and permanently
 * squat the deterministic id. A and B could then never open their own
 * thread: create denied (the doc exists), read denied (they are not
 * participants). Nothing on the client could recover from it, because
 * DmConversation.cidFor(A, B) has exactly one answer.
 *
 * Cases 1–6 all SUCCEED against the pre-fix ruleset; that is what makes
 * them coverage rather than decoration. Case 7 is the declared control —
 * it passes either way. To re-prove the table:
 *   git show 292f376:firestore.rules > /tmp/old.rules
 *   DM_RULES_FILE=/tmp/old.rules node test/dm_rules_cid.test.js
 *
 * Each attack aims at its own virgin cid, so a denial is the binding
 * talking and never "that document already exists".
 *
 * Uids here are underscore-free on purpose: the rule recovers the pair by
 * splitting the cid on '_', the same Firebase-generated-uid assumption
 * storage.rules already documents for dm_images.
 *
 * Unlike the other suites this one reports every case before exiting, so
 * a run against an old ruleset yields the whole before/after table in a
 * single pass instead of stopping at the first surprise.
 *
 * Run with the firestore emulator up:
 *   node test/dm_rules_cid.test.js
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
  doc, getDoc, setDoc, addDoc, collection, serverTimestamp,
} = require('firebase/firestore');

const [HOST, PORT] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
const RULES_FILE =
  process.env.DM_RULES_FILE || resolve(__dirname, '../../firestore.rules');

const A = 'userA';
const B = 'userB';
const C = 'userC';
const D = 'userD';
const E = 'userE';
const F = 'userF';
const G = 'userG';
const H = 'userH';
const I = 'userI';
const X = 'userX';
const ATTACKER = 'attacker';

// Mirrors DmConversation.cidFor: sorted uids joined with '_'.
const cidFor = (a, b) => [a, b].sort().join('_');

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

/** Same shape, participants written verbatim — attackers don't sort. */
const rawPayload = (participants) => ({
  participants,
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  lastMessage: '',
  lastSenderId: '',
  lastReadAt: {},
  blockedBy: [],
});

let failed = 0;
async function run(name, fn) {
  try {
    await fn();
    console.log(`  ok — ${name}`);
  } catch (e) {
    failed++;
    console.log(`  FAIL — ${name}\n         ${e.message}`);
  }
}

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-dm-rules-cid',
    firestore: {
      host: HOST,
      port: Number(PORT),
      rules: readFileSync(RULES_FILE, 'utf8'),
    },
  });
  const db = (uid) => env.authenticatedContext(uid).firestore();
  const convo = (d, cid) => doc(d, 'conversations', cid);
  const messages = (d, cid) => collection(d, 'conversations', cid, 'messages');

  await env.clearFirestore();

  await run('1. attacker cannot squat userA_userB with [attacker, userX], and the real pair still gets their thread', async () => {
    const cid = cidFor(A, B);
    await assertFails(setDoc(convo(db(ATTACKER), cid), rawPayload([ATTACKER, X])));
    // The point of the whole fix: with the squat denied, A and B can open
    // the id that is theirs, read it, and send both directions.
    await assertSucceeds(setDoc(convo(db(A), cid), createPayload(A, B)));
    const snap = await getDoc(convo(db(B), cid));
    assert.strictEqual(snap.id, 'userA_userB', 'cid is the sorted uid pair');
    assert.deepStrictEqual(snap.get('participants'), [A, B]);
    await assertSucceeds(addDoc(messages(db(A), cid),
      { senderId: A, text: 'hi B!', createdAt: serverTimestamp() }));
    await assertSucceeds(addDoc(messages(db(B), cid),
      { senderId: B, text: 'yo!', createdAt: serverTimestamp() }));
  });

  await run('2. partial squat [attacker, userF] on userF_userG is denied', async () => {
    const cid = cidFor(F, G);
    await assertFails(setDoc(convo(db(ATTACKER), cid), rawPayload([ATTACKER, F])));
    // …in both array positions, so this is not an artifact of ordering.
    await assertFails(setDoc(convo(db(ATTACKER), cid), rawPayload([F, ATTACKER])));
  });

  await run('3. reversed cid userB_userA is denied for the right pair', async () => {
    await assertFails(setDoc(convo(db(A), 'userB_userA'), createPayload(A, B)));
  });

  await run('4. cid unrelated to its participants is denied', async () => {
    // userC opens a thread with userD but files it under userH_userI.
    await assertFails(setDoc(convo(db(C), cidFor(H, I)), createPayload(C, D)));
  });

  await run('5. malformed cids are denied', async () => {
    await assertFails(setDoc(convo(db(A), 'nounderscore'), createPayload(A, B)));
    await assertFails(setDoc(convo(db(A), 'userA_userB_userC'), createPayload(A, B)));
    // split('_') yields ['userA', '', 'userB'] — three parts, not two.
    await assertFails(setDoc(convo(db(A), 'userA__userB'), createPayload(A, B)));
  });

  await run('6. cases 2–5 left no document behind', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      for (const cid of [cidFor(F, G), 'userB_userA', cidFor(H, I),
        'nounderscore', 'userA_userB_userC', 'userA__userB']) {
        const snap = await getDoc(doc(ctx.firestore(), 'conversations', cid));
        assert.strictEqual(snap.exists(), false, `${cid} must not exist`);
      }
    });
  });

  await run('7. CONTROL (passes pre-fix too): the later-sorting uid may open the pair', async () => {
    // Case 1 already covered A opening with B. This is B opening with A:
    // a fresh pair, created by the uid that sorts second. Re-using
    // userA_userB here would be a set-on-existing, denied for an unrelated
    // reason, and would prove nothing.
    const cid = cidFor(D, E);
    assert.strictEqual(cid, 'userD_userE');
    await assertSucceeds(setDoc(convo(db(E), cid), createPayload(E, D)));
    const snap = await getDoc(convo(db(D), cid));
    assert.deepStrictEqual(snap.get('participants'), [D, E]);
  });

  await env.cleanup();
  if (failed) {
    console.log(`\n${failed} cid-binding case(s) FAILED.`);
    process.exit(1);
  }
  console.log('\nAll DM cid-binding tests passed.');
  process.exit(0);
})().catch((e) => {
  console.error('\nFAILED:', e.message);
  process.exit(1);
});
