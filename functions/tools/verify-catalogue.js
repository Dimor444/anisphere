#!/usr/bin/env node
/**
 * Reads the catalogue back out of Firestore and diffs it against EVERY
 * hardcoded copy still in the tree.
 *
 * RUN THIS YOURSELF, after the seed:
 *
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *   node functions/tools/verify-catalogue.js
 *
 * This is the checkpoint that makes Phase 2 safe. Phase 2 switches the
 * functions from their hardcoded table to Firestore while OLD CLIENTS are
 * still sending prices from their bundled list — that is only safe if the two
 * already agree, and this is what proves they do.
 *
 * THE COPIES IT CHECKS — read from the real files, never restated here. A
 * verify script that carried its own copy of the values would be one more
 * copy and would agree with itself forever.
 *
 *   1. STORE_ITEMS            functions/index.js          pre-Phase 2 only
 *   2. SPIN_PRIZES            functions/index.js          pre-Phase 2 only
 *   3. SampleData.storeItems  lib/data/sample_data.dart
 *   4. CosmeticSlot._slotOf   lib/services/currency_service.dart
 *   5. _undeliverable         lib/features/wallet/wallet_screen.dart
 *   6. wheel _prizes face     lib/features/wallet/wallet_screen.dart
 *
 * 1 and 2 stop existing when Phase 2 lands, and the script detects which
 * state functions/index.js is in rather than assuming. It does NOT treat
 * their absence as a pass: it insists on a positive marker of the new state,
 * because "the regex found nothing" and "the table is gone" must never be
 * the same observation. 3 to 6 stay hardcoded until Phase 3, and they are
 * what the checkpoint is for now.
 *
 * IT FAILS LOUDLY WHEN IT CANNOT FIND A TABLE. Every extractor asserts it
 * matched something of the expected shape and exits non-zero otherwise,
 * because the dangerous failure for a checkpoint is not a false alarm — it is
 * a regex that quietly matches nothing and reports a clean bill of health.
 *
 * Findings are split:
 *   MISMATCH — a value disagrees. Phase 2 is NOT safe. Exit code 1.
 *   GAP      — a copy does not carry that item or field at all. Expected for
 *              the client, which has no tombstone for the withdrawn item;
 *              this is what Phase 2 removes. Exit code 0.
 */
'use strict';

const path = require('node:path');
const fs = require('node:fs');
const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const ROOT = path.join(__dirname, '..', '..');
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), 'utf8');

const mismatches = [];
const gaps = [];
const bad = (where, msg) => mismatches.push(`${where}: ${msg}`);
const gap = (where, msg) => gaps.push(`${where}: ${msg}`);

function die(msg) {
  console.error(`\n  ✗ EXTRACTION FAILED — ${msg}`);
  console.error('    The checkpoint cannot pass without reading every copy.\n');
  process.exit(2);
}

// ── Extractors ────────────────────────────────────────────────────────────
// Each returns real values parsed from the real file, and dies if the shape
// it expects is not there.

/**
 * Which phase functions/index.js is in.
 *
 * Determined by POSITIVE markers of both states, never by "the regex found
 * nothing so it must be gone" — that is precisely the silent failure this
 * script exists to avoid. A file matching neither marker is an unknown state
 * and stops the run.
 */
function serverPhase() {
  const src = read('functions/index.js');
  const hasTable = /const STORE_ITEMS = \{/.test(src);
  const readsFirestore = /const STORE_ITEMS_COLLECTION = /.test(src);
  if (hasTable && readsFirestore) die('functions/index.js has BOTH the hardcoded table and the Firestore read');
  if (hasTable) return 'table';
  if (readsFirestore) return 'firestore';
  die('functions/index.js has neither STORE_ITEMS nor STORE_ITEMS_COLLECTION — unknown state');
}

function serverStoreItems() {
  const src = read('functions/index.js');
  const block = src.match(/const STORE_ITEMS = \{([\s\S]*?)\n\};/);
  if (!block) die('STORE_ITEMS block not found in functions/index.js');
  const out = {};
  const re = /^\s{2}([a-z0-9_]+):\s*\{([^}]*)\},/gm;
  let m;
  while ((m = re.exec(block[1])) !== null) {
    const [, id, body] = m;
    const pick = (k) => {
      const v = body.match(new RegExp(`${k}:\\s*('([^']*)'|true|false|\\d+)`));
      if (!v) return undefined;
      if (v[2] !== undefined) return v[2];
      if (v[1] === 'true') return true;
      if (v[1] === 'false') return false;
      return Number(v[1]);
    };
    out[id] = { price: pick('price'), sellable: pick('sellable'), slot: pick('slot'), unavailable: pick('unavailable') };
  }
  if (Object.keys(out).length === 0) die('STORE_ITEMS parsed to zero entries');
  return out;
}

function serverSpinPrizes() {
  const m = read('functions/index.js').match(/const SPIN_PRIZES = \[([^\]]+)\];/);
  if (!m) die('SPIN_PRIZES not found in functions/index.js');
  const arr = m[1].split(',').map((s) => Number(s.trim()));
  if (arr.length === 0 || arr.some(Number.isNaN)) die('SPIN_PRIZES did not parse to numbers');
  return arr;
}

function clientStoreItems() {
  const src = read('lib/data/sample_data.dart');
  const block = src.match(/static const List<StoreItem> storeItems = \[([\s\S]*?)\n  \];/);
  if (!block) die('storeItems list not found in lib/data/sample_data.dart');
  const out = {};
  const re = /StoreItem\('([^']+)',\s*'([^']*)',\s*'([^']*)',\s*(\d+),/g;
  let m;
  while ((m = re.exec(block[1])) !== null) {
    out[m[1]] = { name: m[2], sub: m[3], price: Number(m[4]) };
  }
  if (Object.keys(out).length === 0) die('client storeItems parsed to zero entries');
  return out;
}

function clientSlotOf() {
  const src = read('lib/services/currency_service.dart');
  const block = src.match(/static const Map<String, String> _slotOf = \{([\s\S]*?)\};/);
  if (!block) die('_slotOf map not found in lib/services/currency_service.dart');
  const out = {};
  const re = /'([a-z0-9_]+)':\s*([a-zA-Z]+),/g;
  let m;
  while ((m = re.exec(block[1])) !== null) out[m[1]] = m[2];
  if (Object.keys(out).length === 0) die('_slotOf parsed to zero entries');
  return out;
}

function clientUndeliverable() {
  const m = read('lib/features/wallet/wallet_screen.dart')
    .match(/static const Set<String> _undeliverable = \{([^}]*)\};/);
  if (!m) die('_undeliverable set not found in lib/features/wallet/wallet_screen.dart');
  const ids = [...m[1].matchAll(/'([a-z0-9_]+)'/g)].map((x) => x[1]);
  if (ids.length === 0) die('_undeliverable parsed to zero entries');
  return new Set(ids);
}

function clientWheelPrizes() {
  const m = read('lib/features/wallet/wallet_screen.dart')
    .match(/static const _prizes = \[([^\]]+)\];/);
  if (!m) die('wheel _prizes face not found in lib/features/wallet/wallet_screen.dart');
  const arr = m[1].split(',').map((s) => Number(s.trim()));
  if (arr.length === 0 || arr.some(Number.isNaN)) die('wheel _prizes did not parse to numbers');
  return arr;
}

// ── Compare ───────────────────────────────────────────────────────────────

(async () => {
  // After Phase 2 the server has no hardcoded copy to compare — it reads the
  // same Firestore the client will. The CLIENT copies are still hardcoded
  // until Phase 3, and they are the whole point of the checkpoint now.
  const phase = serverPhase();
  const srvItems = phase === 'table' ? serverStoreItems() : null;
  const srvPrizes = phase === 'table' ? serverSpinPrizes() : null;
  const cliItems = clientStoreItems();
  const cliSlots = clientSlotOf();
  const cliUndel = clientUndeliverable();
  const cliWheel = clientWheelPrizes();

  console.log(`\n  functions/index.js: ${phase === 'table' ? 'hardcoded table (pre-Phase 2)' : 'reads Firestore (Phase 2 done)'}`);
  console.log('\n  extracted:');
  if (phase === 'table') {
    console.log(`    STORE_ITEMS            ${Object.keys(srvItems).length} items`);
    console.log(`    SPIN_PRIZES            [${srvPrizes.join(', ')}]`);
  } else {
    console.log('    STORE_ITEMS            — deleted, server reads store_items');
    console.log('    SPIN_PRIZES            — deleted, server reads config/spin_wheel');
  }
  console.log(`    SampleData.storeItems  ${Object.keys(cliItems).length} items`);
  console.log(`    _slotOf                ${Object.keys(cliSlots).length} entries`);
  console.log(`    _undeliverable         ${[...cliUndel].join(', ')}`);
  console.log(`    wheel _prizes          [${cliWheel.join(', ')}]`);

  // Proves the six extractors actually matched, without credentials or a
  // network. Worth its own flag: the dangerous failure here is a regex that
  // matches nothing and lets the checkpoint pass, so being able to eyeball
  // what was parsed is part of trusting the result.
  if (process.argv.includes('--extract-only')) {
    console.log('\n  --extract-only: parsing verified, Firestore not contacted.\n');
    process.exit(0);
  }

  initializeApp({ credential: applicationDefault() });
  const db = getFirestore();

  const snap = await db.collection('store_items').get();
  if (snap.empty) die('store_items is EMPTY in Firestore — run the seed first');
  const fs_items = {};
  snap.forEach((d) => (fs_items[d.id] = d.data()));

  const cfg = await db.collection('config').doc('spin_wheel').get();
  if (!cfg.exists) die('config/spin_wheel is MISSING in Firestore — run the seed first');
  const fs_prizes = cfg.get('prizes');
  if (!Array.isArray(fs_prizes)) die('config/spin_wheel.prizes is not an array');

  console.log(`\n  firestore: ${Object.keys(fs_items).length} store_items, prizes [${fs_prizes.join(', ')}]\n`);

  const sameArr = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

  // 1+2. The server's own copies — only while they still exist. Once the
  // functions read Firestore there is nothing left to disagree with: the
  // server IS the catalogue, so comparing it to itself would prove nothing.
  if (phase === 'table') {
    for (const [id, fsIt] of Object.entries(fs_items)) {
      const s = srvItems[id];
      if (!s) { gap('STORE_ITEMS', `${id} absent`); continue; }
      if (s.price !== fsIt.price) bad('STORE_ITEMS', `${id}.price ${s.price} ≠ ${fsIt.price}`);
      if (s.sellable !== fsIt.sellable) bad('STORE_ITEMS', `${id}.sellable ${s.sellable} ≠ ${fsIt.sellable}`);
      if ((s.slot ?? null) !== (fsIt.slot ?? null)) bad('STORE_ITEMS', `${id}.slot ${s.slot} ≠ ${fsIt.slot}`);
      if ((s.unavailable ?? null) !== (fsIt.unavailable ?? null)) bad('STORE_ITEMS', `${id}.unavailable ${s.unavailable} ≠ ${fsIt.unavailable}`);
    }
    for (const id of Object.keys(srvItems)) {
      if (!fs_items[id]) bad('STORE_ITEMS', `${id} missing from Firestore`);
    }
    if (!sameArr(srvPrizes, fs_prizes)) bad('SPIN_PRIZES', `[${srvPrizes}] ≠ [${fs_prizes}]`);
  }

  // 3. Client shop list — name, sub, price. No tombstone, by construction.
  for (const [id, fsIt] of Object.entries(fs_items)) {
    const c = cliItems[id];
    if (!c) { gap('SampleData.storeItems', `${id} absent (client has no tombstone)`); continue; }
    if (c.price !== fsIt.price) bad('SampleData.storeItems', `${id}.price ${c.price} ≠ ${fsIt.price}`);
    if (c.name !== fsIt.name) bad('SampleData.storeItems', `${id}.name "${c.name}" ≠ "${fsIt.name}"`);
    if (c.sub !== fsIt.sub) bad('SampleData.storeItems', `${id}.sub "${c.sub}" ≠ "${fsIt.sub}"`);
  }

  // 4. Client slot map — only the cosmetics have one.
  for (const [id, fsIt] of Object.entries(fs_items)) {
    if (!fsIt.slot) {
      if (cliSlots[id]) bad('_slotOf', `${id} has slot ${cliSlots[id]} but Firestore has none`);
      continue;
    }
    if (!cliSlots[id]) { gap('_slotOf', `${id} absent`); continue; }
    if (cliSlots[id] !== fsIt.slot) bad('_slotOf', `${id} ${cliSlots[id]} ≠ ${fsIt.slot}`);
  }

  // 5. Client held-back set — should equal the non-sellable ids it knows of.
  for (const [id, fsIt] of Object.entries(fs_items)) {
    const inSet = cliUndel.has(id);
    if (!fsIt.sellable && !inSet) {
      // Only a gap when the client does not carry the item at all.
      if (!cliItems[id]) gap('_undeliverable', `${id} absent (client has no tombstone)`);
      else bad('_undeliverable', `${id} is not sellable but is offered`);
    }
    if (fsIt.sellable && inSet) bad('_undeliverable', `${id} is sellable but held back`);
  }

  // 6. The painted wheel face — ORDER matters, the server returns an index.
  if (!sameArr(cliWheel, fs_prizes)) bad('wheel _prizes', `[${cliWheel}] ≠ [${fs_prizes}]`);

  // ── Report ──────────────────────────────────────────────────────────────
  if (gaps.length) {
    console.log('  GAPS — a copy does not carry this at all (Phase 2 removes these):');
    for (const g of gaps) console.log(`    · ${g}`);
    console.log('');
  }
  if (mismatches.length) {
    console.log('  MISMATCHES — values disagree. PHASE 2 IS NOT SAFE:');
    for (const m of mismatches) console.log(`    ✗ ${m}`);
    console.log('');
    process.exit(1);
  }
  console.log('  ✓ zero mismatches — every hardcoded copy agrees with Firestore.\n');
  process.exit(0);
})().catch((e) => die(e.message));
