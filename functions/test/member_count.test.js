/**
 * memberCount handler semantics — and the room ending when it empties or
 * goes idle — against the Firestore emulator.
 *
 * Cloud Functions deliver at-least-once, so the SAME members/{uid} event can
 * invoke the handler more than once, and a redelivery can land AFTER a later
 * event. Driving Firestore cannot reproduce that on demand, so this calls the
 * handler body directly — which is exactly what a redelivery does.
 *
 * The earlier delta-based handler passed a naive version of these tests and
 * still corrupted the count in the real end-to-end run; every case here fixes
 * a specific way that failed.
 *
 * Run with the firestore emulator up:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node test/member_count.test.js
 */

process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
process.env.GCLOUD_PROJECT ||= 'anisphere-36cb0';

const assert = require('node:assert');

const { _syncMemberCount, _sweepStaleRooms } = require('../index.js');
const { getFirestore } = require('firebase-admin/firestore');

const db = getFirestore();
const roomRef = (id) => db.collection('rooms').doc(id);

/** A room with [memberUids] actually present in members/, count seeded wrong. */
async function seedRoom(id, memberUids, seededCount = 0) {
  const ref = roomRef(id);
  const existing = await ref.collection('members').get();
  await Promise.all(existing.docs.map((d) => d.ref.delete()));
  await ref.set({
    type: 'watch_party',
    title: `ZZ Count ${id}`,
    hostUid: 'zzhost',
    memberCount: seededCount,
    isLive: true,
    createdAt: new Date(),
  });
  await Promise.all(
    memberUids.map((u) => ref.collection('members').doc(u).set({ joinedAt: new Date() })),
  );
}

const countOf = async (id) => (await roomRef(id).get()).get('memberCount');
const exists = async (id) => (await roomRef(id).get()).exists;

async function run(name, fn) {
  await fn();
  console.log(`  ok — ${name}`);
}

(async () => {
  await run('counts the members that actually exist', async () => {
    await seedRoom('zz_c_basic', ['a', 'b', 'c']);
    await _syncMemberCount('zz_c_basic');
    assert.strictEqual(await countOf('zz_c_basic'), 3);
  });

  await run('redelivered join is idempotent — no double count', async () => {
    await seedRoom('zz_c_redeliver', ['a']);
    await _syncMemberCount('zz_c_redeliver');
    assert.strictEqual(await countOf('zz_c_redeliver'), 1, 'first delivery');

    // The redelivery of that same create event.
    await _syncMemberCount('zz_c_redeliver');
    await _syncMemberCount('zz_c_redeliver');
    assert.strictEqual(await countOf('zz_c_redeliver'), 1, 'redeliveries must not inflate');
  });

  await run('join redelivered AFTER the leave cannot resurrect the room (the observed bug)', async () => {
    // Exactly the sequence the e2e run hit: join fires, leave fires, then the
    // create event is delivered again with the member doc already gone. The
    // delta handler ended at 1 with zero members and never recovered. Now the
    // leave empties the room and ends it, and the late join is a no-op.
    await seedRoom('zz_c_late', ['a']);
    await _syncMemberCount('zz_c_late'); // join
    assert.strictEqual(await countOf('zz_c_late'), 1);

    await roomRef('zz_c_late').collection('members').doc('a').delete();
    assert.strictEqual(await _syncMemberCount('zz_c_late'), true, 'last leave reports the room ended');
    assert.strictEqual(await exists('zz_c_late'), false, 'an empty room ends');

    assert.strictEqual(await _syncMemberCount('zz_c_late'), false); // late redelivery of the join
    assert.strictEqual(await exists('zz_c_late'), false, 'stale join redelivery must not resurrect the room');
  });

  await run('a leave that leaves others behind does not end the room', async () => {
    await seedRoom('zz_c_stay', ['a', 'b']);
    await _syncMemberCount('zz_c_stay');
    await roomRef('zz_c_stay').collection('members').doc('a').delete();
    assert.strictEqual(await _syncMemberCount('zz_c_stay'), false);
    assert.strictEqual(await countOf('zz_c_stay'), 1);
  });

  await run('a wrongly-high seed with nobody in it ends, never goes negative', async () => {
    await seedRoom('zz_c_neg', [], 5);
    await _syncMemberCount('zz_c_neg');
    assert.strictEqual(await exists('zz_c_neg'), false);
  });

  await run('self-heals drift from a wrongly-low seed', async () => {
    await seedRoom('zz_c_drift', ['a', 'b'], 0);
    await _syncMemberCount('zz_c_drift');
    assert.strictEqual(await countOf('zz_c_drift'), 2, 'next event repairs earlier drift');
  });

  await run('concurrent invocations do not lose updates', async () => {
    await seedRoom('zz_c_race', ['a', 'b', 'c', 'd']);
    await Promise.all([
      _syncMemberCount('zz_c_race'),
      _syncMemberCount('zz_c_race'),
      _syncMemberCount('zz_c_race'),
    ]);
    assert.strictEqual(await countOf('zz_c_race'), 4);
  });

  await run('a deleted room is a no-op, not a crash', async () => {
    await _syncMemberCount('zz_room_that_never_existed');
  });

  await run('sweep ends idle old rooms and keeps the rest', async () => {
    const HOUR = 60 * 60 * 1000;
    const now = Date.now();
    const seedAt = async (id, createdAgo, joinedAgo) => {
      await seedRoom(id, []);
      await roomRef(id).update({ createdAt: new Date(now - createdAgo), memberCount: 1 });
      await roomRef(id).collection('members').doc('m').set({ joinedAt: new Date(now - joinedAgo), uid: 'm' });
    };
    // The pre-leaving shape: an old room whose only membership went stale.
    await seedAt('zz_s_stale', 30 * HOUR, 30 * HOUR);
    // Old, but someone joined an hour ago — a party that is still going.
    await seedAt('zz_s_active', 30 * HOUR, 1 * HOUR);
    // Young — inside the window whatever its members are doing.
    await seedAt('zz_s_young', 1 * HOUR, 1 * HOUR);

    const ended = await _sweepStaleRooms(now);
    assert.ok(ended.includes('zz_s_stale'), 'stale room is swept');
    assert.strictEqual(await exists('zz_s_stale'), false);
    const orphans = await roomRef('zz_s_stale').collection('members').get();
    assert.strictEqual(orphans.size, 0, 'the sweep takes the roster with the room');
    assert.strictEqual(await exists('zz_s_active'), true, 'a room still being joined is kept');
    assert.strictEqual(await exists('zz_s_young'), true, 'a young room is kept');
  });

  console.log('\nAll memberCount tests passed.');
  process.exit(0);
})().catch((e) => {
  console.error('\nFAILED:', e.message);
  process.exit(1);
});
