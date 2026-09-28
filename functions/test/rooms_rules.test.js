/**
 * Rooms security-rules contract for ending and leaving, against the Firestore
 * emulator.
 *
 * Rooms now end — the host deletes one, or it empties — so a join has to land
 * in a room that still exists. The create path writes the room and the host's
 * membership in ONE batch, which is why the rule uses existsAfter: case 1 is
 * the one that fails if it is ever "simplified" to exists.
 *
 * RULES_FILE points the suite at another ruleset, which is how the negative
 * controls run: against the rules before this change, the cases marked
 * [new rule] must fail.
 *
 * Run with the firestore emulator up:
 *   node test/rooms_rules.test.js
 *   RULES_FILE=/path/to/old.rules node test/rooms_rules.test.js
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
  doc, getDoc, setDoc, deleteDoc, writeBatch, serverTimestamp,
} = require('firebase/firestore');

const [HOST, PORT] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
const RULES = process.env.RULES_FILE || resolve(__dirname, '../../firestore.rules');

const HOSTUID = 'host';
const GUEST = 'guest';
const ROOM = 'room1';

/** The exact payload Room.toCreateMap() produces. */
const roomPayload = (hostUid) => ({
  type: 'watch_party',
  title: 'Frieren ep 28',
  hostUid,
  memberCount: 0,
  isLive: true,
  createdAt: serverTimestamp(),
});

/** The exact payload RoomService._membership() produces. */
const memberPayload = (uid) => ({ joinedAt: serverTimestamp(), uid });

async function run(name, fn) {
  await fn();
  console.log(`  ok — ${name}`);
}

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-rooms-rules',
    firestore: { host: HOST, port: Number(PORT), rules: readFileSync(RULES, 'utf8') },
  });
  const db = (uid) => env.authenticatedContext(uid).firestore();
  const roomRef = (d, id = ROOM) => doc(d, 'rooms', id);
  const memberRef = (d, uid, id = ROOM) => doc(d, 'rooms', id, 'members', uid);

  await env.clearFirestore();
  console.log(`rules: ${RULES}`);

  await run('1. host creates room + own membership in one batch [existsAfter]', async () => {
    const d = db(HOSTUID);
    const batch = writeBatch(d);
    batch.set(roomRef(d), roomPayload(HOSTUID));
    batch.set(memberRef(d, HOSTUID), memberPayload(HOSTUID));
    await assertSucceeds(batch.commit());
  });

  await run('2. a guest joins a room that exists', async () => {
    await assertSucceeds(setDoc(memberRef(db(GUEST), GUEST), memberPayload(GUEST)));
  });

  await run('3. a guest cannot join a room that does not exist [new rule]', async () => {
    await assertFails(setDoc(memberRef(db(GUEST), GUEST, 'no_such_room'), memberPayload(GUEST)));
  });

  await run('4. a guest cannot end someone else\'s room', async () => {
    await assertFails(deleteDoc(roomRef(db(GUEST))));
    let exists;
    await env.withSecurityRulesDisabled(async (c) => {
      exists = (await getDoc(roomRef(c.firestore()))).exists();
    });
    assert.strictEqual(exists, true, 'room must survive the refused delete');
  });

  await run('5. a guest cannot remove the host\'s membership', async () => {
    await assertFails(deleteDoc(memberRef(db(GUEST), HOSTUID)));
  });

  await run('6. the host ends the room', async () => {
    await assertSucceeds(deleteDoc(roomRef(db(HOSTUID))));
  });

  await run('7. a late join into the ended room is refused [new rule]', async () => {
    // Clear the guest's own membership first (the server trigger does this in
    // production), so this is a fresh create rather than an update.
    await env.withSecurityRulesDisabled((c) => deleteDoc(memberRef(c.firestore(), GUEST)));
    await assertFails(setDoc(memberRef(db(GUEST), GUEST), memberPayload(GUEST)));
  });

  await run('8. leaving still works after the room is gone (dispose after End)', async () => {
    await assertSucceeds(deleteDoc(memberRef(db(HOSTUID), HOSTUID)));
  });

  await env.cleanup();
  console.log('\nAll rooms rules tests passed.');
  process.exit(0);
})().catch((e) => {
  console.error('\nFAILED:', e.message);
  process.exit(1);
});
