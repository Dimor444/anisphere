/**
 * Ani Videos create/update contract, against the Firestore emulator.
 *
 * A video's urls must be the exact R2 keys the upload grant signs for this
 * author and this document, on an allowed public host; the author snapshot
 * stored beside it (name, avatar, badge) must be the author's real values;
 * the document must have the shape the app writes, a server date, a duration
 * of at least a second, an AniList cover or none, and an upload grant behind
 * it; and none of what is checked at create can be undone by an update.
 *
 * Cases are tagged:
 *   [compat]     what installed builds send — must pass under any rules
 *   [unchanged]  what both this ruleset and the one before it decide the same
 *                way: the url and identity refusals, and the edits still open
 *   [new rule]   a write the previous rules allowed — an attack, or an upload
 *                on a host that has been retired — must be refused now
 *   [transition] a host added to a list, nothing else changed
 *
 * Every refusal starts from a payload that passes and changes one thing, and
 * every create but the grant cases has its grant, so a case is refused for
 * the reason its name gives.
 *
 * RULES_FILE points the suite at another ruleset, which is how the negative
 * control runs: against the rules before a change, exactly the cases that
 * change introduces must fail — its [new rule] cases, which those rules let
 * through — and every other case must pass. The hypothetical-host
 * [transition] cases rewrite the current rules' text, so they are skipped
 * under RULES_FILE.
 *
 * Run with the firestore emulator up:
 *   node test/ani_videos_rules.test.js
 *   RULES_FILE=/path/to/old.rules node test/ani_videos_rules.test.js
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
  doc, setDoc, updateDoc, writeBatch, serverTimestamp, increment, Timestamp,
} = require('firebase/firestore');

const [HOST, PORT] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
const RULES = process.env.RULES_FILE || resolve(__dirname, '../../firestore.rules');

// The bucket's custom domain: what the upload function hands out, and the
// one listed host.
const BASE = 'https://media.4nisphere.com';
// The bucket's default public host, which the custom domain replaced. Every
// stored video was rewritten off it and it is no longer listed.
const R2_DEV = 'https://pub-d6e4c414f2c04681bbafc54bd2375308.r2.dev';
// A host no ruleset lists, for the "one more entry" cases.
const CUSTOM = 'https://videos.example.com';
const ANILIST = 'https://s4.anilist.co';
const ANILIST_NEXT = 'https://s5.anilist.co';
const COVERS = '/file/anilistcdn/media/anime/cover/medium/';
// What AniList returns as coverImage.large for Frieren (154587).
const FRIEREN_COVER = `${ANILIST}${COVERS}bx154587-qQTzQnEJJ3oB.jpg`;
const ALICE = 'alice';
const BOB = 'bob';
const VERA = 'vera'; // verified

/** The exact payload AniVideoData.toMap() produces in uploadVideo. */
function videoPayload(uid, videoId, profile, overrides = {}) {
  return {
    userId: uid,
    userName: profile ? (profile.displayName.trim() || profile.userName) : '',
    userAvatar: profile ? profile.userAvatar : '',
    isVerified: profile ? profile.isVerified : false,
    videoUrl: `${BASE}/ani_videos/${uid}/${videoId}.mp4`,
    thumbnailUrl: `${BASE}/ani_videos/${uid}/${videoId}.jpg`,
    caption: 'ZZRules clip #frieren',
    anilist_id: 154587,
    animeTitle: 'Frieren: Beyond Journey’s End',
    animeCover: FRIEREN_COVER,
    hashtags: ['frieren'],
    durationSeconds: 30,
    likes: 0,
    commentsCount: 0,
    shareCount: 0,
    viewCount: 0,
    createdAt: serverTimestamp(),
    isSpoiler: false,
    ...overrides,
  };
}

const PROFILES = {
  [ALICE]: { userName: 'alice_h', displayName: 'Alice', userAvatar: 'https://cdn.example/alice.jpg', isVerified: false },
  [BOB]: { userName: 'bob_h', displayName: '', userAvatar: '', isVerified: false },
  [VERA]: { userName: 'vera_h', displayName: 'Vera', userAvatar: '', isVerified: true },
};

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

async function makeEnv(projectId, rules) {
  const env = await initializeTestEnvironment({
    projectId,
    firestore: { host: HOST, port: Number(PORT), rules },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const [uid, p] of Object.entries(PROFILES)) {
      await setDoc(doc(ctx.firestore(), 'users', uid), p);
    }
  });
  return env;
}

let n = 0;
const id = () => `zzrules${String(++n).padStart(13, '0')}`; // 20 chars, like an auto id

/** What requestVideoUploadUrl writes before it signs: upload_grants/{uid}_{videoId}. */
function grant(env, uid, videoId) {
  return env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), 'upload_grants', `${uid}_${videoId}`), { uid, videoId, tier: 'guest' }));
}

/**
 * uploadVideo's final write, as [uid]. [overrides] is an object or a function
 * of the video id. The grant is issued first unless [granted] is false.
 */
async function upload(env, uid, overrides = {}, { profile = PROFILES[uid], granted = true, videoId = id() } = {}) {
  if (granted) await grant(env, uid, videoId);
  const extra = typeof overrides === 'function' ? overrides(videoId) : overrides;
  return setDoc(doc(env.authenticatedContext(uid).firestore(), 'ani_videos', videoId),
    videoPayload(uid, videoId, profile, extra));
}

/** A video already stored, written past the rules. */
async function stored(env, uid, overrides = {}) {
  const v = id();
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), 'ani_videos', v), videoPayload(uid, v, PROFILES[uid], overrides)));
  return v;
}

(async () => {
  const rules = readFileSync(RULES, 'utf8');
  const env = await makeEnv('demo-anivideos-rules', rules);
  const as = (uid) => env.authenticatedContext(uid).firestore();
  const ok = (uid, overrides, opts) => assertSucceeds(upload(env, uid, overrides, opts));
  const refused = (uid, overrides, opts) => assertFails(upload(env, uid, overrides, opts));

  console.log(`ani_videos rules — ${process.env.RULES_FILE ? `RULES_FILE=${RULES}` : 'current rules'}`);

  // ── Installed builds keep uploading ───────────────────────────────────
  await run('[compat]', 'installed-build upload, display name set', () => ok(ALICE));
  await run('[compat]', 'installed-build upload, no display name (handle as name)', () => ok(BOB));
  await run('[compat]', 'thumbnail failed, stored as empty', () => ok(ALICE, { thumbnailUrl: '' }));
  await run('[compat]', 'profile read failed, empty snapshot', () => ok(ALICE, {}, { profile: null }));
  await run('[compat]', 'verified author stores the badge', () => ok(VERA));
  await run('[compat]', 'no anime tagged: id, title and cover all null', () =>
    ok(ALICE, { anilist_id: null, animeTitle: null, animeCover: null }));
  await run('[compat]', 'anime whose AniList entry has no cover: empty', () => ok(ALICE, { animeCover: '' }));
  await run('[compat]', "AniList's placeholder cover", () => ok(ALICE, { animeCover: `${ANILIST}${COVERS}default.jpg` }));
  await run('[compat]', 'a .png cover with an n-prefixed name', () =>
    ok(ALICE, { animeCover: `${ANILIST}${COVERS}nx99423-8MBxtwCeHf8B.png` }));
  await run('[compat]', 'a sub-second clip, rounded up to 1', () => ok(ALICE, { durationSeconds: 1 }));
  await run('[compat]', 'a 120-second clip', () => ok(ALICE, { durationSeconds: 120 }));
  await run('[compat]', 'no caption, no hashtags', () => ok(ALICE, { caption: '', hashtags: [] }));
  await run('[compat]', 'the upload batch with its trending hashtag', async () => {
    const v = id();
    await grant(env, ALICE, v);
    const db = as(ALICE);
    const batch = writeBatch(db);
    batch.set(doc(db, 'ani_videos', v), videoPayload(ALICE, v, PROFILES[ALICE]));
    batch.set(doc(db, 'trending_hashtags', 'frieren'),
      { tag: 'frieren', count: increment(1), lastUsed: serverTimestamp() }, { merge: true });
    await assertSucceeds(batch.commit());
  });
  await run('[compat]', 'anyone bumps a view by one', async () => {
    const v = await stored(env, ALICE);
    await assertSucceeds(updateDoc(doc(as(BOB), 'ani_videos', v), { viewCount: increment(1) }));
  });
  await run('[compat]', 'a like still lands on a stored video of the wrong shape', async () => {
    const v = await stored(env, ALICE, { createdAt: 'zzz', animeCover: 'https://evil.example/c.jpg' });
    // likeVideo's batch: the like and the count together.
    const db = as(BOB);
    await assertSucceeds(writeBatch(db)
      .set(doc(db, 'ani_videos', v, 'likes', BOB), { likedAt: serverTimestamp(), uid: BOB })
      .update(doc(db, 'ani_videos', v), { likes: increment(1) })
      .commit());
  });

  // ── Urls the upload path never produced (the previous change) ─────────
  await run('[unchanged]', 'video on another host', () =>
    refused(ALICE, (v) => ({ videoUrl: `https://evil.example/ani_videos/${ALICE}/${v}.mp4` })));
  await run('[unchanged]', "video pointing at another author's object", () =>
    refused(ALICE, (v) => ({ videoUrl: `${BASE}/ani_videos/${BOB}/${v}.mp4` })));
  await run('[unchanged]', "video pointing at the author's other video", () =>
    refused(ALICE, { videoUrl: `${BASE}/ani_videos/${ALICE}/zzother0000000000001.mp4` }));
  await run('[unchanged]', 'video key with the wrong extension', () =>
    refused(ALICE, (v) => ({ videoUrl: `${BASE}/ani_videos/${ALICE}/${v}.jpg` })));
  await run('[unchanged]', 'video url with a query string', () =>
    refused(ALICE, (v) => ({ videoUrl: `${BASE}/ani_videos/${ALICE}/${v}.mp4?x=1` })));
  await run('[unchanged]', 'video url with the path repeated under another prefix', () =>
    refused(ALICE, (v) => ({ videoUrl: `https://evil.example/x/ani_videos/${ALICE}/${v}.mp4` })));
  await run('[unchanged]', 'thumbnail on another host', () =>
    refused(ALICE, { thumbnailUrl: 'https://evil.example/t.jpg' }));

  // ── An author snapshot that isn't the author (the previous change) ────
  await run('[unchanged]', "someone else's name", () => refused(ALICE, { userName: 'AniSphere Official' }));
  await run('[unchanged]', 'a badge the author does not have', () => refused(ALICE, { isVerified: true }));
  await run('[unchanged]', "an avatar that is not the author's", () =>
    refused(ALICE, { userAvatar: 'https://evil.example/a.jpg' }));
  await run('[unchanged]', 'a clip over 120 seconds', () => refused(ALICE, { durationSeconds: 121 }));

  // ── A. The shape the app writes ───────────────────────────────────────
  await run('[new rule]', 'createdAt stored as text', () => refused(ALICE, { createdAt: 'zzz' }));
  await run('[new rule]', "createdAt from the client's clock, an hour ahead", () =>
    refused(ALICE, { createdAt: Timestamp.fromMillis(Date.now() + 3600 * 1000) }));
  await run('[new rule]', 'a field the app never writes', () => refused(ALICE, { featured: true }));
  await run('[new rule]', 'hashtags that are not a list', () => refused(ALICE, { hashtags: 'frieren' }));
  await run('[new rule]', 'more hashtags than a caption can hold', () =>
    refused(ALICE, { hashtags: Array.from({ length: 101 }, (_, i) => `t${i}`) }));
  await run('[new rule]', 'isSpoiler as text', () => refused(ALICE, { isSpoiler: 'yes' }));
  await run('[new rule]', 'anilist_id as text', () => refused(ALICE, { anilist_id: '154587' }));
  await run('[new rule]', 'animeTitle as a number', () => refused(ALICE, { animeTitle: 7 }));

  // ── B. The upload grant ───────────────────────────────────────────────
  await run('[new rule]', 'no upload grant', () => refused(ALICE, {}, { granted: false }));
  await run('[new rule]', "another author's grant for the same video id", async () => {
    const v = id();
    await grant(env, BOB, v);
    await assertFails(upload(env, ALICE, {}, { videoId: v, granted: false }));
  });
  await run('[new rule]', 'a video id that is not a 20-character auto id', () =>
    refused(ALICE, {}, { videoId: 'zz_short_id' }));

  // ── C. The anime cover ────────────────────────────────────────────────
  await run('[new rule]', 'cover on another host', () => refused(ALICE, { animeCover: 'https://evil.example/c.jpg' }));
  await run('[new rule]', 'an AniList user avatar (user-uploaded) as the cover', () =>
    refused(ALICE, { animeCover: `${ANILIST}/file/anilistcdn/user/avatar/large/b5678-abcdefgh.png` }));
  await run('[new rule]', 'cover url with a query string', () => refused(ALICE, { animeCover: `${FRIEREN_COVER}?x=1` }));

  // ── D. The duration ───────────────────────────────────────────────────
  await run('[new rule]', 'a zero-second clip', () => refused(ALICE, { durationSeconds: 0 }));
  await run('[new rule]', 'a negative duration', () => refused(ALICE, { durationSeconds: -5 }));

  // ── After create ──────────────────────────────────────────────────────
  const existing = await stored(env, ALICE);
  const edit = (data) => updateDoc(doc(as(ALICE), 'ani_videos', existing), data);
  await run('[unchanged]', 'author swaps the video url after create', () =>
    assertFails(edit({ videoUrl: 'https://evil.example/v.mp4' })));
  await run('[unchanged]', 'author grants itself a badge after create', () => assertFails(edit({ isVerified: true })));
  await run('[unchanged]', 'author renames itself on the video after create', () =>
    assertFails(edit({ userName: 'AniSphere Official' })));
  await run('[unchanged]', 'author edits the caption within the limit', () =>
    assertSucceeds(edit({ caption: 'ZZRules edited', hashtags: [] })));
  await run('[new rule]', 'caption edited to a number', () => assertFails(edit({ caption: 42 })));
  await run('[new rule]', 'caption edited past 200 characters', () => assertFails(edit({ caption: 'x'.repeat(201) })));
  await run('[new rule]', 'createdAt moved after create', () =>
    assertFails(edit({ createdAt: Timestamp.fromMillis(Date.now() + 3600 * 1000) })));
  await run('[new rule]', 'durationSeconds changed after create', () => assertFails(edit({ durationSeconds: 0 })));
  await run('[new rule]', 'a field added after create', () => assertFails(edit({ featured: true })));
  await run('[new rule]', 'cover swapped to another host after create', () =>
    assertFails(edit({ animeCover: 'https://evil.example/c.jpg' })));
  await run('[new rule]', 'isSpoiler edited to text', () => assertFails(edit({ isSpoiler: 'yes' })));
  await run('[new rule]', 'a video like with another field', async () => {
    const v = await stored(env, ALICE);
    await assertFails(setDoc(doc(as(BOB), 'ani_videos', v, 'likes', BOB),
      { likedAt: serverTimestamp(), uid: BOB, weight: 100 }));
  });
  await run('[new rule]', 'a video like dated by the client', async () => {
    const v = await stored(env, ALICE);
    await assertFails(setDoc(doc(as(BOB), 'ani_videos', v, 'likes', BOB), { likedAt: Timestamp.now(), uid: BOB }));
  });
  await run('[new rule]', 'a like on a video that does not exist', () => {
    const db = as(BOB);
    return assertFails(setDoc(doc(db, 'ani_videos', 'zznosuchvideo0000001', 'likes', BOB),
      { likedAt: serverTimestamp(), uid: BOB }));
  });

  // ── media.4nisphere.com in, r2.dev out ────────────────────────────────
  // Every [compat] upload above is on media.4nisphere.com: it is the base the
  // upload function hands out, so it is what installed builds now send.
  await run('[compat]', 'an upload on media.4nisphere.com, the custom domain', () => ok(ALICE));
  await run('[unchanged]', "media.4nisphere.com pointing at another author's object, refused", () =>
    refused(ALICE, (v) => ({ videoUrl: `${BASE}/ani_videos/${BOB}/${v}.mp4` })));
  const onR2Dev = (v) => ({
    videoUrl: `${R2_DEV}/ani_videos/${ALICE}/${v}.mp4`,
    thumbnailUrl: `${R2_DEV}/ani_videos/${ALICE}/${v}.jpg`,
  });
  await run('[new rule]', 'an upload on r2.dev', () => refused(ALICE, onR2Dev));
  await run('[new rule]', 'an upload with only its video on r2.dev', () =>
    refused(ALICE, (v) => ({ videoUrl: onR2Dev(v).videoUrl })));
  await run('[new rule]', 'an upload with only its thumbnail on r2.dev', () =>
    refused(ALICE, (v) => ({ thumbnailUrl: onR2Dev(v).thumbnailUrl })));
  // The url check runs at create only and no update may touch a url, so a
  // video stored on either host stays editable whatever the list says.
  await run('[unchanged]', 'a video stored on media.4nisphere.com: its author can still edit the caption', async () => {
    const v = await stored(env, ALICE);
    await assertSucceeds(updateDoc(doc(as(ALICE), 'ani_videos', v), { caption: 'ZZRules edited after the move' }));
  });
  await run('[unchanged]', 'a video still stored on r2.dev: its author can still edit the caption', async () => {
    const v = id();
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'ani_videos', v),
      videoPayload(ALICE, v, PROFILES[ALICE], onR2Dev(v))));
    await assertSucceeds(updateDoc(doc(as(ALICE), 'ani_videos', v), { caption: 'ZZRules edited, still on r2.dev' }));
  });

  await env.cleanup();

  // ── A host is one more list entry ─────────────────────────────────────
  if (!process.env.RULES_FILE) {
    const swap = (text, from, to, what) => {
      if (!text.includes(from)) throw new Error(`${what} list not found in the rules`);
      return text.replace(from, to);
    };
    let variant = swap(rules, `return ['${BASE}'];`, `return ['${BASE}', '${CUSTOM}'];`, 'aniVideoBases()');
    variant = swap(variant, `return ['${ANILIST}'];`, `return ['${ANILIST}', '${ANILIST_NEXT}'];`, 'aniListImageHosts()');
    const env2 = await makeEnv('demo-anivideos-transition', variant);
    const ok2 = (uid, overrides) => assertSucceeds(upload(env2, uid, overrides));
    const refused2 = (uid, overrides) => assertFails(upload(env2, uid, overrides));
    await run('[transition]', 'custom video domain accepted once listed', () =>
      ok2(ALICE, (v) => ({
        videoUrl: `${CUSTOM}/ani_videos/${ALICE}/${v}.mp4`,
        thumbnailUrl: `${CUSTOM}/ani_videos/${ALICE}/${v}.jpg`,
      })));
    await run('[transition]', 'media.4nisphere.com still accepted alongside it', () => ok2(ALICE));
    await run('[transition]', 'an unlisted video host still refused', () =>
      refused2(ALICE, (v) => ({ videoUrl: `https://evil.example/ani_videos/${ALICE}/${v}.mp4` })));
    await run('[transition]', 'a second AniList image host accepted once listed', () =>
      ok2(ALICE, { animeCover: `${ANILIST_NEXT}${COVERS}bx154587-qQTzQnEJJ3oB.jpg` }));
    await run('[transition]', 'an unlisted image host still refused', () =>
      refused2(ALICE, { animeCover: `https://img.example${COVERS}bx154587-qQTzQnEJJ3oB.jpg` }));
    await env2.cleanup();
  }

  const failed = results.filter((r) => !r.ok);
  const count = (t) => {
    const all = results.filter((r) => r.tag === t);
    return `${t} ${all.filter((r) => r.ok).length}/${all.length}`;
  };
  console.log(`\n${results.length - failed.length}/${results.length} passed — ` +
    ['[compat]', '[unchanged]', '[new rule]', '[transition]'].map(count).join(', '));
  process.exit(failed.length ? 1 : 0);
})().catch((e) => {
  console.error('\nSUITE ERROR:', e.message);
  process.exit(2);
});
