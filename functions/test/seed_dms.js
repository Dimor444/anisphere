/**
 * Deterministic DM seed for the LOCAL EMULATOR: rebuilds the two demo
 * threads (Rin: unread, Kaito: read + an 80-message paged history) from
 * scratch, for any app uid. Replaces the old committed emulator-data
 * export — run this instead of importing mutable state.
 *
 * The app signs itself in (Continue as Guest) and prints its uid in a
 * snackbar; pass that uid here. Run from functions/ with the Firestore
 * emulator up:
 *   node test/seed_dms.js <appUid>
 *
 * Idempotent: doc ids are deterministic (cidFor + fixed message slots),
 * so re-running overwrites the same docs rather than duplicating.
 */
process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
process.env.GCLOUD_PROJECT ||= 'anisphere-36cb0';

const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

const appUid = process.argv[2];
if (!appUid) throw new Error('usage: node test/seed_dms.js <appUid>');

initializeApp();
const db = getFirestore();

const cidFor = (a, b) => [a, b].sort().join('_');
const minsAgo = (m) => Timestamp.fromMillis(Date.now() - m * 60_000);

const RIN = 'seed_rin';
const KAITO = 'seed_kaito';

const profile = (uid, userName, displayName, bio, isVerified, countryCode, createdMins) => ({
  userId: uid,
  userName,
  userNameLower: userName,
  displayName,
  userAvatar: '',
  bio,
  isVerified,
  isPlus: false,
  countryCode,
  followerCount: 0, followingCount: 0, postsCount: 0,
  isPrivate: false,
  createdAt: minsAgo(createdMins),
});

(async () => {
  await db.doc(`users/${RIN}`).set(
    profile(RIN, 'rin_nakamura', 'Rin Nakamura', 'Frieren enjoyer', true, 'JP', 60 * 24 * 30));
  await db.doc(`users/${KAITO}`).set(
    profile(KAITO, 'kaito_amv', 'Kaito', 'AMV editor', false, 'XX', 60 * 24 * 60));

  // Claim the app user's handle so the username gate stays quiet on launch.
  const me = await db.doc(`users/${appUid}`).get();
  const handle = me.exists ? (me.get('userNameLower') || me.get('userName')) : null;
  if (handle) await db.doc(`usernames/${handle}`).set({ uid: appUid });

  // Thread 1 — Rin, unread (2 messages newer than the app user's read mark).
  const cid1 = cidFor(appUid, RIN);
  await db.doc(`conversations/${cid1}`).set({
    participants: [appUid, RIN].sort(),
    createdAt: minsAgo(60 * 24),
    updatedAt: minsAgo(2),
    lastMessage: 'Did you see Frieren ep 28?! 😭',
    lastSenderId: RIN,
    lastReadAt: { [appUid]: minsAgo(60), [RIN]: minsAgo(1) },
    blockedBy: [],
  });
  const m1 = (slot) => db.doc(`conversations/${cid1}/messages/seed_${slot}`);
  await m1('a').set({ senderId: appUid, text: 'Episode night? 🍿', createdAt: minsAgo(60 * 24) });
  await m1('b').set({ senderId: RIN, text: 'The ending had me in tears', createdAt: minsAgo(3) });
  await m1('c').set({ senderId: RIN, text: 'Did you see Frieren ep 28?! 😭', createdAt: minsAgo(2) });

  // Thread 2 — Kaito, fully read, with an 80-message history for pagination.
  const cid2 = cidFor(appUid, KAITO);
  await db.doc(`conversations/${cid2}`).set({
    participants: [appUid, KAITO].sort(),
    createdAt: minsAgo(60 * 48),
    updatedAt: minsAgo(180),
    lastMessage: 'That AMV was fire 🔥',
    lastSenderId: appUid,
    lastReadAt: { [appUid]: minsAgo(120), [KAITO]: minsAgo(170) },
    blockedBy: [],
  });
  const m2 = (slot) => db.doc(`conversations/${cid2}/messages/seed_${slot}`);
  await m2('a').set({ senderId: KAITO, text: 'New Solo Leveling AMV is up!', createdAt: minsAgo(240) });
  await m2('b').set({ senderId: appUid, text: 'That AMV was fire 🔥', createdAt: minsAgo(180) });
  let batch = db.batch();
  for (let i = 0; i < 80; i++) {
    batch.set(m2(`h${String(i).padStart(2, '0')}`), {
      senderId: i % 2 === 0 ? KAITO : appUid,
      text: `history #${i}`,
      // Strictly older than the two "recent" messages above.
      createdAt: minsAgo(60 * 10 - i),
    });
    if (i % 40 === 39) { await batch.commit(); batch = db.batch(); }
  }

  console.log(`seeded for ${appUid}:`);
  console.log(`  ${cid1} — 3 messages, unread for the app user`);
  console.log(`  ${cid2} — 82 messages (80 history), fully read`);
  process.exit(0);
})().catch((e) => { console.error('SEED FAILED:', e); process.exit(1); });
