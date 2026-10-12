/**
 * Ani Videos create/update contract, against the Firestore emulator.
 *
 * A video's urls must be the exact R2 keys the upload grant signs for this
 * author and this document, on an allowed public host; the author snapshot
 * stored beside it (name, avatar, badge) must be the author's real values;
 * and none of those can be changed after create.
 *
 * Cases are tagged:
 *   [compat]     what installed builds send today — must pass under any rules
 *   [new rule]   an attack the old rule allowed — must be refused now
 *   [transition] a second public host added to the list, nothing else changed
 *
 * RULES_FILE points the suite at another ruleset, which is how the negative
 * control runs: against the rules before this change, exactly the [new rule]
 * cases must fail (the attacks go through) and every [compat] case must pass.
 * [transition] needs the current rules and is skipped under RULES_FILE.
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
const { doc, setDoc, updateDoc, serverTimestamp, increment } = require('firebase/firestore');

const [HOST, PORT] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
const RULES = process.env.RULES_FILE || resolve(__dirname, '../../firestore.rules');

const BASE = 'https://pub-d6e4c414f2c04681bbafc54bd2375308.r2.dev';
const CUSTOM = 'https://videos.example.com';
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
    caption: 'ZZRules clip',
    anilist_id: 154587,
    animeTitle: 'Frieren',
    animeCover: 'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/x.jpg',
    hashtags: [],
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

(async () => {
  const rules = readFileSync(RULES, 'utf8');
  const env = await makeEnv('demo-anivideos-rules', rules);
  const as = (uid) => env.authenticatedContext(uid).firestore();
  let n = 0;
  const id = () => `zzrules${String(++n).padStart(13, '0')}`; // 20 chars, like an auto id

  console.log(`ani_videos rules — ${process.env.RULES_FILE ? `RULES_FILE=${RULES}` : 'current rules'}`);

  // ── Installed builds keep uploading ───────────────────────────────────
  await run('[compat]', 'installed-build upload, display name set', async () => {
    const v = id();
    await assertSucceeds(setDoc(doc(as(ALICE), 'ani_videos', v), videoPayload(ALICE, v, PROFILES[ALICE])));
  });
  await run('[compat]', 'installed-build upload, no display name (handle as name)', async () => {
    const v = id();
    await assertSucceeds(setDoc(doc(as(BOB), 'ani_videos', v), videoPayload(BOB, v, PROFILES[BOB])));
  });
  await run('[compat]', 'thumbnail failed, stored as empty', async () => {
    const v = id();
    await assertSucceeds(setDoc(doc(as(ALICE), 'ani_videos', v),
      videoPayload(ALICE, v, PROFILES[ALICE], { thumbnailUrl: '' })));
  });
  await run('[compat]', 'profile read failed, empty snapshot', async () => {
    const v = id();
    await assertSucceeds(setDoc(doc(as(ALICE), 'ani_videos', v), videoPayload(ALICE, v, null)));
  });
  await run('[compat]', 'verified author stores the badge', async () => {
    const v = id();
    await assertSucceeds(setDoc(doc(as(VERA), 'ani_videos', v), videoPayload(VERA, v, PROFILES[VERA])));
  });
  await run('[compat]', 'anyone bumps a view by one', async () => {
    const v = id();
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'ani_videos', v), videoPayload(ALICE, v, PROFILES[ALICE]));
    });
    await assertSucceeds(updateDoc(doc(as(BOB), 'ani_videos', v), { viewCount: increment(1) }));
  });

  // ── Urls the upload path never produced ───────────────────────────────
  await run('[new rule]', 'video on another host', async () => {
    const v = id();
    await assertFails(setDoc(doc(as(ALICE), 'ani_videos', v),
      videoPayload(ALICE, v, PROFILES[ALICE], { videoUrl: `https://evil.example/ani_videos/${ALICE}/${v}.mp4` })));
  });
  await run('[new rule]', "video pointing at another author's object", async () => {
    const v = id();
    await assertFails(setDoc(doc(as(ALICE), 'ani_videos', v),
      videoPayload(ALICE, v, PROFILES[ALICE], { videoUrl: `${BASE}/ani_videos/${BOB}/${v}.mp4` })));
  });
  await run('[new rule]', "video pointing at the author's other video", async () => {
    const v = id();
    await assertFails(setDoc(doc(as(ALICE), 'ani_videos', v),
      videoPayload(ALICE, v, PROFILES[ALICE], { videoUrl: `${BASE}/ani_videos/${ALICE}/zzother0000000000001.mp4` })));
  });
  await run('[new rule]', 'video key with the wrong extension', async () => {
    const v = id();
    await assertFails(setDoc(doc(as(ALICE), 'ani_videos', v),
      videoPayload(ALICE, v, PROFILES[ALICE], { videoUrl: `${BASE}/ani_videos/${ALICE}/${v}.jpg` })));
  });
  await run('[new rule]', 'video url with a query string', async () => {
    const v = id();
    await assertFails(setDoc(doc(as(ALICE), 'ani_videos', v),
      videoPayload(ALICE, v, PROFILES[ALICE], { videoUrl: `${BASE}/ani_videos/${ALICE}/${v}.mp4?x=1` })));
  });
  await run('[new rule]', 'video url with the path repeated under another prefix', async () => {
    const v = id();
    await assertFails(setDoc(doc(as(ALICE), 'ani_videos', v),
      videoPayload(ALICE, v, PROFILES[ALICE], { videoUrl: `https://evil.example/x/ani_videos/${ALICE}/${v}.mp4` })));
  });
  await run('[new rule]', 'thumbnail on another host', async () => {
    const v = id();
    await assertFails(setDoc(doc(as(ALICE), 'ani_videos', v),
      videoPayload(ALICE, v, PROFILES[ALICE], { thumbnailUrl: 'https://evil.example/t.jpg' })));
  });

  // ── An author snapshot that isn't the author ──────────────────────────
  await run('[new rule]', "someone else's name", async () => {
    const v = id();
    await assertFails(setDoc(doc(as(ALICE), 'ani_videos', v),
      videoPayload(ALICE, v, PROFILES[ALICE], { userName: 'AniSphere Official' })));
  });
  await run('[new rule]', 'a badge the author does not have', async () => {
    const v = id();
    await assertFails(setDoc(doc(as(ALICE), 'ani_videos', v),
      videoPayload(ALICE, v, PROFILES[ALICE], { isVerified: true })));
  });
  await run('[new rule]', "an avatar that is not the author's", async () => {
    const v = id();
    await assertFails(setDoc(doc(as(ALICE), 'ani_videos', v),
      videoPayload(ALICE, v, PROFILES[ALICE], { userAvatar: 'https://evil.example/a.jpg' })));
  });

  // ── Fixed after create ────────────────────────────────────────────────
  const existing = id();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'ani_videos', existing), videoPayload(ALICE, existing, PROFILES[ALICE]));
  });
  await run('[new rule]', 'author swaps the video url after create', async () => {
    await assertFails(updateDoc(doc(as(ALICE), 'ani_videos', existing), { videoUrl: 'https://evil.example/v.mp4' }));
  });
  await run('[new rule]', 'author grants itself a badge after create', async () => {
    await assertFails(updateDoc(doc(as(ALICE), 'ani_videos', existing), { isVerified: true }));
  });
  await run('[new rule]', 'author renames itself on the video after create', async () => {
    await assertFails(updateDoc(doc(as(ALICE), 'ani_videos', existing), { userName: 'AniSphere Official' }));
  });

  await env.cleanup();

  // ── A second host is one more list entry ──────────────────────────────
  if (!process.env.RULES_FILE) {
    const listed = `return ['${BASE}'];`;
    if (!rules.includes(listed)) throw new Error('aniVideoBases() list not found in the rules');
    const withCustom = rules.replace(listed, `return ['${BASE}', '${CUSTOM}'];`);
    const env2 = await makeEnv('demo-anivideos-transition', withCustom);
    const as2 = (uid) => env2.authenticatedContext(uid).firestore();
    await run('[transition]', 'custom domain accepted once listed', async () => {
      const v = id();
      await assertSucceeds(setDoc(doc(as2(ALICE), 'ani_videos', v), videoPayload(ALICE, v, PROFILES[ALICE], {
        videoUrl: `${CUSTOM}/ani_videos/${ALICE}/${v}.mp4`,
        thumbnailUrl: `${CUSTOM}/ani_videos/${ALICE}/${v}.jpg`,
      })));
    });
    await run('[transition]', 'r2.dev still accepted alongside it', async () => {
      const v = id();
      await assertSucceeds(setDoc(doc(as2(ALICE), 'ani_videos', v), videoPayload(ALICE, v, PROFILES[ALICE])));
    });
    await run('[transition]', 'an unlisted host still refused', async () => {
      const v = id();
      await assertFails(setDoc(doc(as2(ALICE), 'ani_videos', v), videoPayload(ALICE, v, PROFILES[ALICE], {
        videoUrl: `https://evil.example/ani_videos/${ALICE}/${v}.mp4`,
      })));
    });
    await env2.cleanup();
  }

  const failed = results.filter((r) => !r.ok);
  const by = (t) => results.filter((r) => r.tag === t);
  console.log(`\n${results.length - failed.length}/${results.length} passed` +
    ` — [compat] ${by('[compat]').filter((r) => r.ok).length}/${by('[compat]').length},` +
    ` [new rule] ${by('[new rule]').filter((r) => r.ok).length}/${by('[new rule]').length},` +
    ` [transition] ${by('[transition]').filter((r) => r.ok).length}/${by('[transition]').length}`);
  process.exit(failed.length ? 1 : 0);
})().catch((e) => {
  console.error('\nSUITE ERROR:', e.message);
  process.exit(2);
});
