/**
 * memberCount handler semantics, against the Firestore emulator.
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

const { _syncMemberCount } = require('../index.js');
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

  await run('join redelivered AFTER the leave converges to 0 (the observed bug)', async () => {
    // Exactly the sequence the e2e run hit: join fires, leave fires, then the
    // create event is delivered again with the member doc already gone. The
    // delta handler ended at 1 with zero members and never recovered.
    await seedRoom('zz_c_late', ['a']);
    await _syncMemberCount('zz_c_late'); // join
    assert.strictEqual(await countOf('zz_c_late'), 1);

    await roomRef('zz_c_late').collection('members').doc('a').delete();
    await _syncMemberCount('zz_c_late'); // leave
    assert.strictEqual(await countOf('zz_c_late'), 0);

    await _syncMemberCount('zz_c_late'); // late redelivery of the join
    assert.strictEqual(await countOf('zz_c_late'), 0, 'stale join redelivery must not resurrect a count');
  });

  await run('never goes negative, even from a wrongly-high seed', async () => {
    await seedRoom('zz_c_neg', [], 5);
    await _syncMemberCount('zz_c_neg');
    assert.strictEqual(await countOf('zz_c_neg'), 0);
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

  console.log('\nAll memberCount tests passed.');
  process.exit(0);
})().catch((e) => {
  console.error('\nFAILED:', e.message);
  process.exit(1);
});
