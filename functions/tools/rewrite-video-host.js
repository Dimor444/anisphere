#!/usr/bin/env node
/**
 * Moves stored Ani Video urls from r2.dev to the bucket's custom domain.
 *
 * An ani_videos document stores its video and thumbnail as full urls —
 * `https://pub-….r2.dev/ani_videos/{uid}/{videoId}.mp4` — composed by the app
 * from the base the upload function handed it. The function now hands out
 * https://media.4nisphere.com; this rewrites the documents saved before it, so
 * they play on networks where r2.dev fails TLS.
 *
 * RUN THIS YOURSELF, with application default credentials. It is a DRY RUN
 * unless you pass --apply: it reports how many documents hold the r2.dev base
 * and lists them.
 *
 *   node functions/tools/rewrite-video-host.js            # report only
 *   node functions/tools/rewrite-video-host.js --apply    # rewrite
 *
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node functions/tools/rewrite-video-host.js
 *     reads no credential of any kind — see verify-catalogue.js for why the
 *     Firestore client is constructed directly rather than through
 *     firebase-admin.
 *
 * WHAT IT WRITES
 *   videoUrl and thumbnailUrl, and only where the value starts with the r2.dev
 *   base followed by a slash: that prefix becomes the new base and the path
 *   after it is kept. Nothing else on the document is written.
 *
 * WHAT IT LEAVES, COUNTED
 *   urls on any other host — two early test videos hold Firebase Storage urls
 *   — empty thumbnails (a failed thumbnail upload stores ''), and anything
 *   that is not a string. A host that merely starts with the same characters
 *   is another host, hence the slash.
 *
 * IDEMPOTENT: a rewritten url no longer starts with the r2.dev base, so a
 * second run has nothing to do for it. That is what makes the SECOND PASS
 * safe: run it again more than ten minutes after the upload function's
 * deploy. An upload granted just before the deploy — grants last ten minutes
 * — can still save an r2.dev url, and the second pass catches it.
 *
 * COST: every ani_videos document is read once, two fields each. The whole
 * collection is scanned rather than queried by prefix so the report can count
 * what it leaves alone as well as what it changes.
 *
 * EXIT CODES: 0 nothing left to rewrite · 1 a dry run found work, or writes
 * failed · 2 could not run.
 */
'use strict';

const { Firestore, FieldPath } = require('@google-cloud/firestore');

const PROJECT_ID = 'anisphere-36cb0';
const OLD_BASE = 'https://pub-d6e4c414f2c04681bbafc54bd2375308.r2.dev';
const NEW_BASE = 'https://media.4nisphere.com';
const FIELDS = ['videoUrl', 'thumbnailUrl'];
const PAGE = 500;
const APPLY = process.argv.includes('--apply');

function die(msg) {
  console.error(`\n  ✗ COULD NOT RUN — ${msg}\n`);
  process.exit(2);
}

const db = new Firestore({ projectId: PROJECT_ID });

/** What one stored url is, and what it becomes (null: left as it is). */
function classify(value) {
  if (value === undefined || value === null) return ['absent', null];
  if (typeof value !== 'string') return ['not a string (left alone)', null];
  if (value === '') return ['empty (left alone)', null];
  if (value.startsWith(`${OLD_BASE}/`)) return ['on r2.dev', NEW_BASE + value.slice(OLD_BASE.length)];
  if (value.startsWith(`${NEW_BASE}/`)) return ['already on the new host', null];
  return ['another host (left alone)', null];
}

const pending = [];              // [ref, { field: newUrl }, [fields]]
const tally = {};
const bump = (group, key) => {
  tally[group] = tally[group] || {};
  tally[group][key] = (tally[group][key] || 0) + 1;
};

async function scan() {
  let last = null;
  for (;;) {
    let q = db.collection('ani_videos').orderBy(FieldPath.documentId()).select(...FIELDS).limit(PAGE);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) return;
    for (const d of snap.docs) {
      bump('ani_videos', 'scanned');
      const update = {};
      for (const field of FIELDS) {
        const [kind, next] = classify(d.get(field));
        bump(field, kind);
        if (next !== null) update[field] = next;
      }
      const changed = Object.keys(update);
      if (changed.length) {
        bump('ani_videos', APPLY ? 'rewritten' : 'to rewrite');
        pending.push([d.ref, update, changed]);
      }
    }
    last = snap.docs[snap.docs.length - 1];
  }
}

(async () => {
  const target = process.env.FIRESTORE_EMULATOR_HOST
    ? `emulator ${process.env.FIRESTORE_EMULATOR_HOST}` : `production ${PROJECT_ID}`;
  console.log(`\n  video host rewrite — ${target} — ${APPLY ? 'APPLYING' : 'DRY RUN (pass --apply to rewrite)'}`);
  console.log(`    ${OLD_BASE}/…  →  ${NEW_BASE}/…`);

  try {
    await scan();
  } catch (e) {
    die(`scan failed: ${e.message}`);
  }

  if (pending.length) {
    console.log(`\n  documents holding the r2.dev base (${pending.length})`);
    for (const [ref, , changed] of pending) console.log(`    ${ref.id}  ${changed.join(', ')}`);
  }

  let failed = 0;
  if (APPLY && pending.length) {
    const writer = db.bulkWriter();
    let gone = 0;
    writer.onWriteError((err) => {
      // A video deleted between the scan and the write has nothing left to move.
      if (err.code === 5 /* NOT_FOUND */) { gone++; return false; }
      return err.failedAttempts < 5;
    });
    const results = pending.map(([ref, update]) => writer.update(ref, update).catch((e) => {
      if (e.code !== 5) failed++;
    }));
    await writer.close();
    await Promise.all(results);
    if (gone) bump('writes', 'skipped — deleted since the scan');
    if (failed) bump('writes', 'FAILED');
  }

  for (const [group, counts] of Object.entries(tally)) {
    console.log(`\n  ${group}`);
    for (const [k, n] of Object.entries(counts)) console.log(`    ${String(n).padStart(7)}  ${k}`);
  }

  if (failed) {
    console.log(`\n  ✗ ${failed} write(s) failed. Re-run: it only touches what still holds r2.dev.\n`);
    process.exit(1);
  }
  if (!APPLY && pending.length) {
    console.log(`\n  ${pending.length} document(s) would be rewritten. Re-run with --apply to rewrite.\n`);
    process.exit(1);
  }
  console.log(APPLY ? `\n  ✓ rewrote ${pending.length} document(s).\n` : '\n  ✓ nothing holds r2.dev — nothing to rewrite.\n');
  process.exit(0);
})().catch((e) => die(e.stack || e.message));
