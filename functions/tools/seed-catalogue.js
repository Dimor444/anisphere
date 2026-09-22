#!/usr/bin/env node
/**
 * Pushes functions/tools/catalogue.json into Firestore.
 *
 * RUN THIS YOURSELF. It authenticates with Application Default Credentials —
 * it does not read, decode or transmit any stored token, and nothing here
 * touches the firebase-tools credential store.
 *
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *   node functions/tools/seed-catalogue.js
 *
 * Add --dry-run to print what it WOULD write and exit without writing.
 *
 * IDEMPOTENT, in the two different senses the two shapes need:
 *
 *   store_items/{itemId}  merge-written, keyed by item id. Re-running with an
 *                         edited price updates that field and leaves the rest;
 *                         re-running unchanged is a no-op write.
 *
 *   config/spin_wheel     FULLY OVERWRITTEN, not merged. The prize array is
 *                         atomic by design — its ORDER is what the server
 *                         returns an index into — and a merge could leave a
 *                         longer old array partially overwritten by a shorter
 *                         new one, which is the exact corruption the single
 *                         document exists to prevent.
 *
 * It does NOT delete rows that have left the json. A catalogue that deletes
 * is a catalogue that can orphan a ledger entry; retiring an item means
 * setting sellable:false, not removing it.
 */
'use strict';

const path = require('node:path');
const fs = require('node:fs');
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const DRY = process.argv.includes('--dry-run');
const SRC = path.join(__dirname, 'catalogue.json');

function die(msg) {
  console.error(`\n  ✗ ${msg}\n`);
  process.exit(1);
}

const raw = JSON.parse(fs.readFileSync(SRC, 'utf8'));
const items = raw.storeItems;
const prizes = raw.spinWheel && raw.spinWheel.prizes;

// Validate BEFORE writing anything. A half-seeded catalogue is worse than an
// unseeded one: the functions would start refusing real items as unknown.
if (!items || typeof items !== 'object') die('catalogue.json has no storeItems object.');
if (!Array.isArray(prizes) || prizes.length === 0) die('catalogue.json has no spinWheel.prizes array.');

const SLOTS = ['frame', 'postBorder', 'nameEffect'];
for (const [id, it] of Object.entries(items)) {
  if (!/^[a-z0-9_]+$/.test(id)) die(`item id "${id}" is not a lowercase slug.`);
  if (typeof it.name !== 'string' || !it.name) die(`${id}: name must be a non-empty string.`);
  if (typeof it.sub !== 'string') die(`${id}: sub must be a string.`);
  if (!Number.isInteger(it.price) || it.price <= 0) die(`${id}: price must be a positive integer.`);
  if (typeof it.sellable !== 'boolean') die(`${id}: sellable must be a boolean.`);
  if (it.slot !== undefined && !SLOTS.includes(it.slot)) die(`${id}: unknown slot "${it.slot}".`);
  // A thing that cannot be sold has to say why, or the UI cannot tell
  // "not yet" from "never again".
  if (!it.sellable && !it.unavailable) die(`${id}: sellable:false needs an unavailable reason.`);
  if (it.sellable && it.unavailable) die(`${id}: sellable:true must not carry unavailable.`);
}
for (const p of prizes) {
  if (!Number.isInteger(p) || p <= 0) die(`spin prize ${p} must be a positive integer.`);
}

console.log(`\n  catalogue.json → ${Object.keys(items).length} items, ${prizes.length} prizes`);
for (const [id, it] of Object.entries(items)) {
  const tag = it.sellable ? `${it.price}g` : `${it.price}g (${it.unavailable})`;
  console.log(`    ${id.padEnd(24)} ${String(it.slot || '—').padEnd(12)} ${tag}`);
}
console.log(`    spin prizes: [${prizes.join(', ')}]`);

if (DRY) {
  console.log('\n  --dry-run: nothing written.\n');
  process.exit(0);
}

initializeApp({ credential: applicationDefault() });
const db = getFirestore();

(async () => {
  const batch = db.batch();
  for (const [id, it] of Object.entries(items)) {
    batch.set(db.collection('store_items').doc(id), it, { merge: true });
  }
  // Overwrite, not merge — see the header.
  batch.set(db.collection('config').doc('spin_wheel'), { prizes });
  await batch.commit();
  console.log(`\n  ✓ wrote ${Object.keys(items).length} store_items + config/spin_wheel\n`);
  process.exit(0);
})().catch((e) => die(e.message));
