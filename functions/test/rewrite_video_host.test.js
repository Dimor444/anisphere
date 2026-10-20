/**
 * functions/tools/rewrite-video-host.js, against the Firestore emulator.
 *
 * Seeds ani_videos with every kind of stored url the script will meet — r2.dev
 * on both fields, r2.dev with an empty or absent thumbnail, a video already on
 * the new host, Firebase Storage urls, a mixed pair, and a host that merely
 * begins like r2.dev's — then runs the script itself, exactly as it would be
 * run against production: a dry run, --apply, a dry run that must find
 * nothing, --apply again, and a late upload for the second pass.
 *
 * Every document's every field is compared before and after: only the r2.dev
 * urls may change, only by their base, and nothing else on any document.
 *
 * Run with the firestore emulator up:
 *   node test/rewrite_video_host.test.js
 */

process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';

const { execFileSync } = require('node:child_process');
const { resolve } = require('node:path');
const { isDeepStrictEqual } = require('node:util');
const { Firestore, Timestamp } = require('@google-cloud/firestore');

const PROJECT_ID = 'anisphere-36cb0';
const OLD = 'https://pub-d6e4c414f2c04681bbafc54bd2375308.r2.dev';
const NEW = 'https://media.4nisphere.com';
const STORAGE = 'https://firebasestorage.googleapis.com/v0/b/anisphere-36cb0.appspot.com/o';
const SCRIPT = resolve(__dirname, '../tools/rewrite-video-host.js');

const db = new Firestore({ projectId: PROJECT_ID });

const results = [];
async function run(name, fn) {
  try {
    await fn();
    results.push({ name, ok: true });
    console.log(`  ok   ${name}`);
  } catch (e) {
    results.push({ name, ok: false });
    console.log(`  FAIL ${name} — ${String(e.message || e).split('\n')[0]}`);
  }
}
function expect(cond, msg) { if (!cond) throw new Error(msg); }

/** Runs the script as an operator would; returns its exit code and output. */
function script(...args) {
  try {
    const out = execFileSync('node', [SCRIPT, ...args], { env: process.env, encoding: 'utf8' });
    return { code: 0, out };
  } catch (e) {
    return { code: e.status, out: `${e.stdout || ''}${e.stderr || ''}` };
  }
}

const path = (uid, v, ext) => `/ani_videos/${uid}/${v}${ext}`;
const video = (id, uid, videoBase, thumb, extra = {}) => ({
  id,
  data: {
    userId: uid,
    caption: `ZZRewrite ${id}`,
    likes: 3,
    viewCount: 12,
    durationSeconds: 30,
    createdAt: Timestamp.fromMillis(1790000000000),
    videoUrl: `${videoBase}${path(uid, id, '.mp4')}`,
    ...(thumb === undefined ? {} : { thumbnailUrl: thumb }),
    ...extra,
  },
});

// What each seeded document must look like afterwards.
const SEED = [
  video('zzr2both', 'alice', OLD, `${OLD}${path('alice', 'zzr2both', '.jpg')}`),
  video('zzr2emptythumb', 'alice', OLD, ''),
  video('zzr2nothumb', 'bob', OLD, undefined),
  video('zzalreadymoved', 'bob', NEW, `${NEW}${path('bob', 'zzalreadymoved', '.jpg')}`),
  video('zzfirebase', 'carol', `${STORAGE}`, `${STORAGE}/thumb.jpg`, {
    videoUrl: `${STORAGE}/ani_videos%2Fcarol%2Fzzfirebase.mp4?alt=media`,
  }),
  video('zzmixed', 'carol', OLD, `${STORAGE}/zzmixed.jpg`),
  video('zzlookalike', 'dave', `${OLD}.evil.example`, `${OLD}.evil.example${path('dave', 'zzlookalike', '.jpg')}`),
];
const expected = (doc) => {
  const swap = (u) => (typeof u === 'string' && u.startsWith(`${OLD}/`) ? NEW + u.slice(OLD.length) : u);
  const out = { ...doc.data, videoUrl: swap(doc.data.videoUrl) };
  if ('thumbnailUrl' in doc.data) out.thumbnailUrl = swap(doc.data.thumbnailUrl);
  return out;
};
const R2_IDS = ['zzr2both', 'zzr2emptythumb', 'zzr2nothumb', 'zzmixed'];

async function snapshotAll() {
  const snap = await db.collection('ani_videos').get();
  return new Map(snap.docs.map((d) => [d.id, { data: d.data(), updateTime: d.updateTime.toMillis() }]));
}

(async () => {
  // Start from nothing: the script scans the whole collection.
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`could not clear the emulator: ${res.status}`);
  for (const d of SEED) await db.collection('ani_videos').doc(d.id).set(d.data);
  const before = await snapshotAll();
  console.log('rewrite-video-host — emulator');

  await run('dry run: finds exactly the documents holding r2.dev, lists them, exits 1', async () => {
    const { code, out } = script();
    expect(code === 1, `exit ${code}`);
    for (const id of R2_IDS) expect(out.includes(`    ${id}  `), `${id} not listed`);
    for (const id of ['zzalreadymoved', 'zzfirebase', 'zzlookalike']) expect(!out.includes(`    ${id}  `), `${id} listed`);
    expect(out.includes(`${R2_IDS.length} document(s) would be rewritten`), 'wrong count');
  });
  await run('dry run: writes nothing', async () => {
    const now = await snapshotAll();
    for (const [id, b] of before) {
      expect(isDeepStrictEqual(now.get(id).data, b.data) && now.get(id).updateTime === b.updateTime, `${id} changed`);
    }
  });

  await run('--apply: rewrites them, exits 0', async () => {
    const { code, out } = script('--apply');
    expect(code === 0, `exit ${code}\n${out}`);
    expect(out.includes(`rewrote ${R2_IDS.length} document(s)`), 'wrong count');
  });
  await run('--apply: only the r2.dev urls changed, only their base, and nothing else on any document', async () => {
    const now = await snapshotAll();
    for (const d of SEED) {
      const got = now.get(d.id);
      expect(isDeepStrictEqual(got.data, expected(d)), `${d.id}: ${JSON.stringify(got.data)}`);
      const touched = R2_IDS.includes(d.id);
      expect((got.updateTime !== before.get(d.id).updateTime) === touched,
        `${d.id} ${touched ? 'was not' : 'was'} written`);
    }
  });

  await run('a dry run after it finds nothing and exits 0', async () => {
    const { code, out } = script();
    expect(code === 0, `exit ${code}`);
    expect(out.includes('nothing to rewrite'), out);
  });
  await run('--apply again: rewrites nothing, writes nothing', async () => {
    const mid = await snapshotAll();
    const { code, out } = script('--apply');
    expect(code === 0 && out.includes('rewrote 0 document(s)'), `exit ${code}\n${out}`);
    const now = await snapshotAll();
    for (const [id, m] of mid) expect(now.get(id).updateTime === m.updateTime, `${id} written again`);
  });

  await run('the second pass: an upload granted before the switch, saved after the first pass', async () => {
    const late = video('zzlateupload', 'erin', OLD, `${OLD}${path('erin', 'zzlateupload', '.jpg')}`);
    await db.collection('ani_videos').doc(late.id).set(late.data);
    const dry = script();
    expect(dry.code === 1 && dry.out.includes('    zzlateupload  videoUrl, thumbnailUrl') && dry.out.includes('1 document(s) would be rewritten'), dry.out);
    const apply = script('--apply');
    expect(apply.code === 0 && apply.out.includes('rewrote 1 document(s)'), apply.out);
    const got = (await db.collection('ani_videos').doc(late.id).get()).data();
    expect(isDeepStrictEqual(got, expected(late)), JSON.stringify(got));
    expect(script().code === 0, 'a final dry run should find nothing');
  });

  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} passed`);
  process.exit(failed.length ? 1 : 0);
})().catch((e) => {
  console.error('\nSUITE ERROR:', e.message);
  process.exit(2);
});
