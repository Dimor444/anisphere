#!/usr/bin/env node
/**
 * Writes the owner onto documents that are KEYED by their owner's uid but
 * never carried it as a field.
 *
 * A like is posts/{postId}/likes/{uid}; a room membership is
 * rooms/{roomId}/members/{uid}. The owner is right there in the path, but a
 * collection-group query cannot filter on a document id — so "every like this
 * account ever made" is not a query, it is a scan of every like in the
 * database. Account deletion has to find exactly that. Once the owner is a
 * field, it is one indexed query.
 *
 * RUN THIS YOURSELF. It is a DRY RUN unless you pass --write: it touches every
 * like in the database, not a handful of catalogue rows, so reporting first is
 * the default rather than a flag you have to remember.
 *
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     node functions/tools/backfill-owner-fields.js            # report only
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     node functions/tools/backfill-owner-fields.js --write    # apply
 *
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node functions/tools/backfill-owner-fields.js
 *     reads no credential of any kind — see verify-catalogue.js for why the
 *     Firestore client is constructed directly rather than through
 *     firebase-admin.
 *
 * WHAT IT WRITES
 *   likes     posts/{id}/likes, ani_videos/{id}/likes   uid    = the document id
 *   members   rooms/{id}/members                        uid    = the document id
 *   votes     community_votes/{day}/votes               userId = the id's uid prefix
 *
 *   EXCEPT a like on your OWN post. New builds leave uid off those on purpose —
 *   the React-to-posts progress bar counts the likes that carry it — and a
 *   post's likes are deleted with the post, so they never need finding.
 *
 *   Orphans — documents whose parent no longer exists — are written like any
 *   other and counted separately. A deleted post's likes survive the post, and
 *   the deletion job has to find those too.
 *
 * WHAT IT CAN ONLY REPORT
 *   comments missing userId — a comment's id is random, so nothing attributes
 *   it. The rules have required userId on create, so this should be zero.
 *   documents whose owner field DISAGREES with their id — the rules make this
 *   impossible for new writes; any found predate them and are left alone.
 *
 * IDEMPOTENT: only documents missing the field are written, and the value is
 * derived from the document's own path, so a second run has nothing to do.
 *
 * NOT A ONE-OFF while old builds are installed: they keep writing likes and
 * memberships without uid. Each run catches up everything written before it.
 *
 * COST: every like, membership, vote and comment is read once — a missing
 * field cannot be queried for. select() keeps each read to the one field;
 * parent posts are read only for likes that need a verdict.
 *
 * EXIT CODES: 0 nothing left to write · 1 a dry run found work, or writes
 * failed · 2 could not run.
 */
'use strict';

const { Firestore, FieldPath } = require('@google-cloud/firestore');

const PROJECT_ID = 'anisphere-36cb0';
const PAGE = 500;
const WRITE = process.argv.includes('--write');

function die(msg) {
  console.error(`\n  ✗ COULD NOT RUN — ${msg}\n`);
  process.exit(2);
}

const db = new Firestore({ projectId: PROJECT_ID });

/** Every document of a collection group, a page at a time, one field each. */
async function* scan(group, field) {
  let last = null;
  for (;;) {
    let q = db.collectionGroup(group).orderBy(FieldPath.documentId()).select(field).limit(PAGE);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) return;
    yield snap.docs;
    last = snap.docs[snap.docs.length - 1];
  }
}

const pending = [];              // [ref, data]
const tally = {};
const bump = (group, key) => {
  tally[group] = tally[group] || {};
  tally[group][key] = (tally[group][key] || 0) + 1;
};

async function likes() {
  for await (const docs of scan('likes', 'uid')) {
    // Parent posts are needed only for post likes still missing uid — to tell
    // a like on someone else's post from a like on your own.
    const needVerdict = docs.filter((d) => d.get('uid') === undefined && d.ref.parent.parent
      && d.ref.parent.parent.parent.id === 'posts');
    const parents = new Map();
    const unique = [...new Map(needVerdict.map((d) => [d.ref.parent.parent.path, d.ref.parent.parent])).values()];
    if (unique.length) {
      const snaps = await db.getAll(...unique, { fieldMask: ['userId'] });
      for (const s of snaps) parents.set(s.ref.path, s);
    }

    for (const d of docs) {
      const uid = d.get('uid');
      const parent = d.ref.parent.parent;
      const kind = parent ? parent.parent.id : '(root)';
      const group = `likes under ${kind}`;
      bump(group, 'scanned');
      if (uid !== undefined) {
        bump(group, uid === d.id ? 'already carry uid' : 'uid DISAGREES with id (left alone)');
        continue;
      }
      let orphan = false;
      if (kind === 'posts') {
        const post = parents.get(parent.path);
        if (post && post.exists && post.get('userId') === d.id) {
          bump(group, 'own-post like, left without uid (by design)');
          continue;
        }
        orphan = !post || !post.exists;
      } else if (kind !== 'ani_videos') {
        // Video likes need no parent read for a verdict.
        bump(group, 'unexpected parent (left alone)');
        continue;
      }
      bump(group, WRITE ? 'uid written' : 'uid to write');
      if (orphan) bump(group, '  of which orphaned (post deleted)');
      pending.push([d.ref, { uid: d.id }]);
    }
  }
}

async function members() {
  for await (const docs of scan('members', 'uid')) {
    for (const d of docs) {
      const uid = d.get('uid');
      bump('room members', 'scanned');
      if (uid !== undefined) {
        bump('room members', uid === d.id ? 'already carry uid' : 'uid DISAGREES with id (left alone)');
        continue;
      }
      bump('room members', WRITE ? 'uid written' : 'uid to write');
      pending.push([d.ref, { uid: d.id }]);
    }
  }
}

async function votes() {
  for await (const docs of scan('votes', 'userId')) {
    for (const d of docs) {
      bump('community votes', 'scanned');
      const userId = d.get('userId');
      const m = d.id.match(/^([A-Za-z0-9]+)_[1-4]$/);
      if (userId !== undefined) {
        bump('community votes', m && userId === m[1] ? 'already carry userId' : 'userId DISAGREES with id (left alone)');
        continue;
      }
      if (!m) { bump('community votes', 'UNATTRIBUTABLE — id is not {uid}_{slot}'); continue; }
      bump('community votes', WRITE ? 'userId written' : 'userId to write');
      pending.push([d.ref, { userId: m[1] }]);
    }
  }
}

async function comments() {
  for await (const docs of scan('comments', 'userId')) {
    for (const d of docs) {
      bump('comments', 'scanned');
      bump('comments', d.get('userId') === undefined ? 'UNATTRIBUTABLE — no userId, random id' : 'carry userId');
    }
  }
}

(async () => {
  const target = process.env.FIRESTORE_EMULATOR_HOST
    ? `emulator ${process.env.FIRESTORE_EMULATOR_HOST}` : `production ${PROJECT_ID}`;
  console.log(`\n  owner-field backfill — ${target} — ${WRITE ? 'WRITING' : 'DRY RUN (pass --write to apply)'}`);

  try {
    await likes();
    await members();
    await votes();
    await comments();
  } catch (e) {
    die(`scan failed: ${e.message}`);
  }

  let failed = 0;
  if (WRITE && pending.length) {
    const writer = db.bulkWriter();
    let gone = 0;
    writer.onWriteError((err) => {
      // A document deleted between the scan and the write is not a failure:
      // there is nothing left to attribute.
      if (err.code === 5 /* NOT_FOUND */) { gone++; return false; }
      return err.failedAttempts < 5;
    });
    const results = pending.map(([ref, data]) => writer.update(ref, data).catch((e) => {
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
    console.log(`\n  ✗ ${failed} write(s) failed. Re-run: it only touches what is still missing.\n`);
    process.exit(1);
  }
  if (!WRITE && pending.length) {
    console.log(`\n  ${pending.length} document(s) would be written. Re-run with --write to apply.\n`);
    process.exit(1);
  }
  console.log(WRITE ? `\n  ✓ wrote ${pending.length} document(s).\n` : '\n  ✓ nothing to write.\n');
  process.exit(0);
})().catch((e) => die(e.stack || e.message));
