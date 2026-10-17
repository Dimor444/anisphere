/**
 * users/{uid} field types, against the Firestore emulator.
 *
 * The rules admitted displayName, userAvatar, isPrivate and createdAt with no
 * type, while the app reads each with one (UserData.fromDoc). A profile
 * holding text where the app reads true/false threw on read, and one such
 * profile failed every list it was in — follow suggestions, user search. Each
 * of the four must now be absent or hold the type UserData.toMap writes; on
 * an update only the fields the write changes are checked, so a profile
 * stored with a bad value before this change can still be edited.
 *
 * Cases are tagged:
 *   [compat]     what installed builds send — must pass under any rules
 *   [legacy]     a profile stored with a bad value under the old rules is
 *                still editable — must pass under any rules
 *   [unchanged]  refusals both this ruleset and the one before it make
 *   [new rule]   a write the previous rules allowed — must be refused now
 *
 * Every refusal starts from a payload that passes and changes one thing.
 *
 * RULES_FILE points the suite at another ruleset, which is how the negative
 * control runs: against the rules before this change, exactly the [new rule]
 * cases must fail (the writes go through) and every other case must pass.
 *
 * Run with the firestore emulator up:
 *   node test/users_rules.test.js
 *   RULES_FILE=/path/to/old.rules node test/users_rules.test.js
 */

process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';

const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, setDoc, updateDoc, serverTimestamp, increment, Timestamp,
} = require('firebase/firestore');

const [HOST, PORT] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
const RULES = process.env.RULES_FILE || resolve(__dirname, '../../firestore.rules');

/** The exact payload ensureProfile writes for a new guest: UserData.toMap(). */
function profilePayload(uid, overrides = {}) {
  const handle = `anifan_${uid.slice(0, 6).toLowerCase()}`;
  return {
    userId: uid,
    userName: handle,
    userNameLower: handle,
    displayName: 'Anime Fan',
    userAvatar: '',
    bio: '',
    isVerified: false,
    isPlus: false,
    countryCode: 'US',
    followerCount: 0,
    followingCount: 0,
    postsCount: 0,
    isPrivate: false,
    currentStreak: 0,
    longestStreak: 0,
    lastActiveDay: '',
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

const results = [];
async function run(tag, name, fn) {
  try {
    await fn();
    results.push({ tag, name, ok: true });
    console.log(`  ok   ${tag} ${name}`);
  } catch (e) {
    results.push({ tag, name, ok: false });
    console.log(`  FAIL ${tag} ${name} — ${String(e.message || e).split('\n')[0]}`);
  }
}

let n = 0;
const uid = () => `zzusr${String(++n).padStart(23, '0')}`; // 28 chars, like an auth uid

(async () => {
  const rules = readFileSync(RULES, 'utf8');
  const env = await initializeTestEnvironment({
    projectId: 'demo-users-rules',
    firestore: { host: HOST, port: Number(PORT), rules },
  });
  // Each run reuses the same ids, so it starts from nothing: a profile left
  // by the previous run would turn a create case into an update.
  await env.clearFirestore();
  const as = (u) => env.authenticatedContext(u).firestore();
  const create = (u, overrides) => setDoc(doc(as(u), 'users', u), profilePayload(u, overrides));
  /** A profile already stored, written past the rules. */
  const stored = async (overrides = {}) => {
    const u = uid();
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'users', u), profilePayload(u, { createdAt: Timestamp.now(), ...overrides })));
    return u;
  };
  const edit = async (fields, overrides) => {
    const u = await stored(overrides);
    return updateDoc(doc(as(u), 'users', u), fields);
  };

  console.log(`users rules — ${process.env.RULES_FILE ? `RULES_FILE=${RULES}` : 'current rules'}`);

  // ── Installed builds keep working ─────────────────────────────────────
  await run('[compat]', 'ensureProfile creates a new guest', () => assertSucceeds(create(uid())));
  await run('[compat]', 'a profile created with a client date', () =>
    assertSucceeds(create(uid(), { createdAt: Timestamp.now() })));
  await run('[compat]', 'Edit Profile: merge-set of displayName and bio', async () => {
    const u = await stored();
    await assertSucceeds(setDoc(doc(as(u), 'users', u), { displayName: 'Mira', bio: 'hi' }, { merge: true }));
  });
  await run('[compat]', 'Edit Profile: an emptied display name', () => assertSucceeds(edit({ displayName: '' })));
  await run('[compat]', 'the bio alone', () => assertSucceeds(edit({ bio: 'new bio' })));
  await run('[compat]', 'countryCode backfilled on an old profile', () => assertSucceeds(edit({ countryCode: 'JP' })));
  await run('[compat]', 'Anime DNA: pinned ids and first anime', () =>
    assertSucceeds(edit({ dnaPinned: [154587, 21], firstAnimeId: 21 })));
  await run('[compat]', 'a follow bumps the other profile\'s counter', async () => {
    const target = await stored();
    await assertSucceeds(updateDoc(doc(as(uid()), 'users', target), { followerCount: increment(1) }));
  });
  await run('[compat]', 'a daily check-in bumps the streak', async () => {
    const d = new Date();
    const day = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
    const u = await stored();
    await assertSucceeds(updateDoc(doc(as(u), 'users', u), { currentStreak: 1, longestStreak: 1, lastActiveDay: day }));
  });

  // ── A profile stored with a bad value is still its owner's to edit ────
  await run('[legacy]', 'bad isPrivate stored: owner edits the display name', () =>
    assertSucceeds(edit({ displayName: 'Mira' }, { isPrivate: 'yes' })));
  await run('[legacy]', 'bad isPrivate stored: owner sets it to false', () =>
    assertSucceeds(edit({ isPrivate: false }, { isPrivate: 'yes' })));
  await run('[legacy]', 'bad isPrivate stored: a follow still bumps the counter', async () => {
    const target = await stored({ isPrivate: 'yes' });
    await assertSucceeds(updateDoc(doc(as(uid()), 'users', target), { followerCount: increment(1) }));
  });

  // ── Refused before and after ──────────────────────────────────────────
  await run('[unchanged]', 'created verified', () => assertFails(create(uid(), { isVerified: true })));
  await run('[unchanged]', 'created with Plus', () => assertFails(create(uid(), { isPlus: true })));
  await run('[unchanged]', 'created with a gold balance', () => assertFails(create(uid(), { aniGold: 100 })));
  await run('[unchanged]', 'a bio of 151 characters', () => assertFails(edit({ bio: 'x'.repeat(151) })));
  await run('[unchanged]', 'isPlus set by its owner', () => assertFails(edit({ isPlus: true })));
  await run('[unchanged]', "another player's display name", async () => {
    const target = await stored();
    await assertFails(updateDoc(doc(as(uid()), 'users', target), { displayName: 'Mallory' }));
  });

  // ── Types the app reads, which the rules did not check ────────────────
  await run('[new rule]', 'created with isPrivate "yes"', () => assertFails(create(uid(), { isPrivate: 'yes' })));
  await run('[new rule]', 'created with a numeric display name', () => assertFails(create(uid(), { displayName: 42 })));
  await run('[new rule]', 'created with an avatar map', () => assertFails(create(uid(), { userAvatar: { url: 'x' } })));
  await run('[new rule]', 'created with a text date', () => assertFails(create(uid(), { createdAt: '2026-10-17' })));
  await run('[new rule]', 'isPrivate edited to "yes"', () => assertFails(edit({ isPrivate: 'yes' })));
  await run('[new rule]', 'isPrivate edited to 1', () => assertFails(edit({ isPrivate: 1 })));
  await run('[new rule]', 'display name edited to a number', () => assertFails(edit({ displayName: 42 })));
  await run('[new rule]', 'avatar edited to a list', () => assertFails(edit({ userAvatar: ['x'] })));
  await run('[new rule]', 'Edit Profile merge-set with a numeric display name', async () => {
    const u = await stored();
    await assertFails(setDoc(doc(as(u), 'users', u), { displayName: 42, bio: 'hi' }, { merge: true }));
  });

  await env.cleanup();

  const failed = results.filter((r) => !r.ok);
  const count = (t) => {
    const all = results.filter((r) => r.tag === t);
    return `${t} ${all.filter((r) => r.ok).length}/${all.length}`;
  };
  console.log(`\n${results.length - failed.length}/${results.length} passed — ` +
    ['[compat]', '[legacy]', '[unchanged]', '[new rule]'].map(count).join(', '));
  process.exit(failed.length ? 1 : 0);
})().catch((e) => {
  console.error('\nSUITE ERROR:', e.message);
  process.exit(2);
});
