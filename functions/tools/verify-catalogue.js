#!/usr/bin/env node
/**
 * The catalogue drift check.
 *
 * The catalogue has one source — functions/tools/catalogue.json, which a
 * human edits and git reviews — and one live copy in Firestore, which the
 * seed pushes and every reader reads. Nothing keeps them the same: a console
 * edit changes Firestore behind git's back, and a merged edit to the file
 * does nothing until someone runs the seed. This is what notices.
 *
 * WHAT IT CHECKS
 *
 *   DRIFT          catalogue.json against Firestore, field by field, both
 *                  ways. A row only in the file: the seed has not been run. A
 *                  row only in Firestore: added by hand, outside review. A
 *                  field that disagrees, or exists on one side only: a
 *                  console edit. The prize array is compared whole, so ORDER
 *                  counts as much as value — the server returns an index
 *                  into it.
 *
 *                  Values are compared WITH their stored type. The client
 *                  drops a row whose price is not an integer while the server
 *                  still sells it, so 250 stored as a double is drift, not a
 *                  match.
 *
 *   UNDELIVERABLE  Every id sellable in either copy must have art in the
 *                  client. Without it the shop draws the fallback and sells
 *                  something this build does not know — the sticker pack in a
 *                  new form. Every slot a row names must exist in every slot
 *                  list, or the server refuses to equip what it sold.
 *
 *   VOCABULARY     The slot lists kept on purpose — COSMETIC_SLOTS on the
 *                  server, CosmeticSlot on the client, SLOTS in the seed —
 *                  must name the same slots. The script cannot collapse them;
 *                  it can prove they agree. Likewise the collection names the
 *                  server, the client and the seed use. The script reads
 *                  whatever the SERVER reads, so it carries no names of its
 *                  own to drift.
 *
 *   REGRESSION     None of the six deleted hardcoded copies may come back
 *                  under its old name. The likely way back is merging a
 *                  branch cut before they went.
 *
 * EXIT CODES
 *   0  clean.
 *   1  a finding: drift, something undeliverable, vocabulary disagreeing, or
 *      a deleted copy back.
 *   2  could not check: a pattern matched nothing, a file would not parse, or
 *      Firestore could not be read. Never a pass.
 *
 * RUN IT
 *   Production — resolves your credentials, so run it yourself:
 *     GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *       node functions/tools/verify-catalogue.js
 *   The emulator — reads no credential of any kind:
 *     FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node functions/tools/verify-catalogue.js
 *   No Firestore — every check the tree alone can answer, against the file:
 *     node functions/tools/verify-catalogue.js --local
 *
 * IT FAILS LOUDLY WHEN IT CANNOT READ SOMETHING. Every read out of source
 * code anchors on one declaration, asserts it found entries of the expected
 * shape, and exits 2 otherwise — because the dangerous failure for a
 * checkpoint is not a false alarm, it is a pattern that quietly matches
 * nothing and reports a clean bill of health.
 */
'use strict';

const path = require('node:path');
const fs = require('node:fs');

const ROOT = path.join(__dirname, '..', '..');
const PROJECT_ID = 'anisphere-36cb0';
const FIRESTORE_TIMEOUT_MS = 30000;

const FILES = {
  source: 'functions/tools/catalogue.json',
  server: 'functions/index.js',
  seed: 'functions/tools/seed-catalogue.js',
  client: 'lib/services/currency_service.dart',
  wallet: 'lib/features/wallet/wallet_screen.dart',
  sample: 'lib/data/sample_data.dart',
};

function die(msg) {
  console.error(`\n  ✗ COULD NOT CHECK — ${msg}`);
  console.error('    Nothing was verified. This is not a pass.\n');
  process.exit(2);
}

function read(rel) {
  try {
    return fs.readFileSync(path.join(ROOT, rel), 'utf8');
  } catch (e) {
    return die(`cannot read ${rel}: ${e.message}`);
  }
}

const findings = { drift: [], undeliverable: [], vocabulary: [], regression: [] };

// ── Extraction ────────────────────────────────────────────────────────────
// ONE mechanism for every copy read out of source code: anchor on a
// declaration, take its body, match entries of a strict shape inside it, and
// stop the run if any step comes up empty. The same machinery the
// pre-Phase 3 extractors used, made into one pair of functions so every read
// out of Dart or JavaScript fails the same way.

const everyMatch = (re) => new RegExp(re.source, re.flags.includes('g') ? re.flags : `${re.flags}g`);

/**
 * The single match of [anchor] in [src]. None, or more than one, stops the
 * run: two declarations means the script cannot know which one is real.
 */
function declaration(src, where, anchor, what) {
  const found = [...src.matchAll(everyMatch(anchor))];
  if (found.length === 0) die(`${what}: declaration not found in ${where}`);
  if (found.length > 1) die(`${what}: declared ${found.length} times in ${where} — which one is real?`);
  return found[0];
}

/**
 * The entries inside the declaration's body (capture group 1).
 *
 * [loose] guards the other silent failure — a pattern that matches SOME of
 * the entries. It counts everything that looks like an entry; if the strict
 * pattern parsed fewer, an entry is in a shape this script does not
 * understand, and a skipped entry would surface later as a false finding
 * instead of a clear "cannot read".
 */
function entriesIn(body, where, entry, what, loose) {
  const found = [...body.matchAll(everyMatch(entry))];
  if (found.length === 0) die(`${what}: found the declaration in ${where} but no entries of the expected shape`);
  if (loose) {
    const all = [...body.matchAll(everyMatch(loose))].length;
    if (all !== found.length) {
      die(`${what}: ${all} entries in ${where} but only ${found.length} in the expected shape`);
    }
  }
  return found;
}

const entries = (src, where, anchor, entry, what, loose) =>
  entriesIn(declaration(src, where, anchor, what)[1], where, entry, what, loose);

function sourceFile() {
  let raw;
  try {
    raw = JSON.parse(read(FILES.source));
  } catch (e) {
    return die(`${FILES.source} is not valid JSON: ${e.message}`);
  }
  const items = raw && raw.storeItems;
  const spin = raw && raw.spinWheel;
  if (!items || typeof items !== 'object' || Object.keys(items).length === 0) {
    die(`${FILES.source} has no storeItems`);
  }
  if (!spin || !Array.isArray(spin.prizes) || spin.prizes.length === 0) {
    die(`${FILES.source} has no spinWheel.prizes`);
  }
  return { items, spin };
}

/** Ids with an art entry — the keys of _ItemArt._byId. The fallback is not art. */
function artIds() {
  const found = entries(
    read(FILES.wallet), FILES.wallet,
    /static const Map<String, _ItemArt> _byId = \{([\s\S]*?)\n  \};/,
    /^\s*'([a-z0-9_]+)':\s*_ItemArt\(/m,
    'client art map (_ItemArt._byId)',
    /_ItemArt\(/,
  );
  return new Set(found.map((m) => m[1]));
}

const quotedList = (rel, anchor, what) => new Set(
  entries(read(rel), rel, anchor, /'([A-Za-z]+)'/, what, /'[^']*'/).map((m) => m[1]),
);

/** CosmeticSlot.all, resolved through the class's own constants to values. */
function clientSlots() {
  const cls = declaration(read(FILES.client), FILES.client, /class CosmeticSlot \{([\s\S]*?)\n\}/, 'client CosmeticSlot')[1];
  const where = `${FILES.client} (CosmeticSlot)`;
  const values = new Map(
    entriesIn(cls, where, /static const String (\w+) = '([^']+)';/, 'CosmeticSlot constants').map((m) => [m[1], m[2]]),
  );
  const names = entries(cls, where, /static const List<String> all = \[([^\]]*)\];/, /\b([A-Za-z_]\w*)\b/, 'CosmeticSlot.all')
    .map((m) => m[1]);
  return new Set(names.map((n) => values.get(n) ?? die(`CosmeticSlot.all names ${n}, which is not a constant of the class`)));
}

/** Collection names each layer uses. The server's are the ones read. */
function collectionNames() {
  const server = read(FILES.server);
  const client = read(FILES.client);
  const seed = read(FILES.seed);
  const val = (src, where, re, what) => declaration(src, where, re, what)[1];
  const seedConfig = declaration(seed, FILES.seed, /batch\.set\(db\.collection\('([^']+)'\)\.doc\('([^']+)'\)/, 'seed config write');
  return {
    server: {
      items: val(server, FILES.server, /const STORE_ITEMS_COLLECTION = '([^']+)';/, 'STORE_ITEMS_COLLECTION'),
      config: val(server, FILES.server, /const CONFIG_COLLECTION = '([^']+)';/, 'CONFIG_COLLECTION'),
      spinDoc: val(server, FILES.server, /const SPIN_CONFIG_DOC = '([^']+)';/, 'SPIN_CONFIG_DOC'),
    },
    client: {
      items: val(client, FILES.client, /static const String _storeItemsCollection = '([^']+)';/, '_storeItemsCollection'),
      config: val(client, FILES.client, /static const String _configCollection = '([^']+)';/, '_configCollection'),
      spinDoc: val(client, FILES.client, /static const String _spinConfigDoc = '([^']+)';/, '_spinConfigDoc'),
    },
    seed: {
      items: val(seed, FILES.seed, /batch\.set\(db\.collection\('([^']+)'\)\.doc\(id\)/, 'seed store_items write'),
      config: seedConfig[1],
      spinDoc: seedConfig[2],
    },
  };
}

// ── Firestore ─────────────────────────────────────────────────────────────

async function readFirestore(names) {
  // ONE construction for both targets. With FIRESTORE_EMULATOR_HOST set the
  // client talks to the emulator over an insecure channel as "owner" and
  // consults no credential at all; without it, it resolves Application
  // Default Credentials the ordinary way.
  //
  // firebase-admin is deliberately NOT used. Its initializeApp resolves ADC
  // eagerly — reading the stored token file even for an emulator run that
  // ignores it — and its Firestore wrapper refuses any other credential.
  //
  // useBigInt makes stored integers arrive as BigInt and doubles as Number,
  // which is what lets canon() tell 250 from 250.0.
  const { Firestore } = require('@google-cloud/firestore');
  const db = new Firestore({ projectId: PROJECT_ID, useBigInt: true });
  const deadline = new Promise((_, reject) => {
    setTimeout(() => reject(new Error(`no answer in ${FIRESTORE_TIMEOUT_MS / 1000}s`)), FIRESTORE_TIMEOUT_MS).unref();
  });
  try {
    const [itemsSnap, spinSnap] = await Promise.race([
      Promise.all([
        db.collection(names.items).get(),
        db.collection(names.config).doc(names.spinDoc).get(),
      ]),
      deadline,
    ]);
    const items = {};
    itemsSnap.forEach((d) => { items[d.id] = d.data(); });
    return { items, spin: spinSnap.exists ? spinSnap.data() : null };
  } catch (e) {
    return die(`could not read Firestore: ${e.message}`);
  } finally {
    db.terminate().catch(() => {});
  }
}

// ── Comparison ────────────────────────────────────────────────────────────

/**
 * A value as a comparable string, TYPE INCLUDED.
 *
 * From Firestore an integer is a BigInt and a double is a Number. The file
 * cannot say "double" for a whole number, and the seed writes whole numbers
 * as integers, so a whole number in the file means an integer.
 */
function canon(v, fromFirestore) {
  if (v === undefined) return '(absent)';
  if (v === null) return 'null';
  if (typeof v === 'bigint') return `${v}`;
  if (typeof v === 'number') return !fromFirestore && Number.isInteger(v) ? `${v}` : `${v} (double)`;
  if (typeof v === 'string') return JSON.stringify(v);
  if (typeof v === 'boolean') return String(v);
  if (Array.isArray(v)) return `[${v.map((x) => canon(x, fromFirestore)).join(', ')}]`;
  if (typeof v.toDate === 'function') return `timestamp ${v.toDate().toISOString()}`;
  if (Object.getPrototypeOf(v) === Object.prototype) {
    return `{${Object.keys(v).sort().map((k) => `${k}: ${canon(v[k], fromFirestore)}`).join(', ')}}`;
  }
  return `<${(v.constructor && v.constructor.name) || typeof v}>`;
}

const union = (a, b) => [...new Set([...a, ...b])];

function checkDrift(file, live) {
  const drift = (m) => findings.drift.push(m);

  for (const id of Object.keys(file.items)) {
    if (!(id in live.items)) drift(`${id}: in catalogue.json, not in Firestore — the seed has not been run since it was added`);
  }
  for (const id of Object.keys(live.items)) {
    if (!(id in file.items)) drift(`${id}: in Firestore, not in catalogue.json — added by hand, outside review`);
  }
  for (const id of Object.keys(file.items).filter((i) => i in live.items)) {
    const f = file.items[id];
    const l = live.items[id];
    for (const k of union(Object.keys(f), Object.keys(l))) {
      const a = canon(f[k], false);
      const b = canon(l[k], true);
      if (a !== b) drift(`${id}.${k}: file ${a}, Firestore ${b}`);
    }
  }

  if (live.spin === null) {
    drift('config/spin_wheel: not in Firestore — the seed has not been run');
    return;
  }
  for (const k of union(Object.keys(file.spin), Object.keys(live.spin))) {
    const a = canon(file.spin[k], false);
    const b = canon(live.spin[k], true);
    if (a === b) continue;
    const reordered = k === 'prizes' && Array.isArray(live.spin.prizes) &&
      canon([...file.spin.prizes].sort(), false) === canon([...live.spin.prizes].sort(), true);
    drift(`spin_wheel.${k}: file ${a}, Firestore ${b}` +
      (reordered ? ' — same prizes, different ORDER: the wheel would land on the wrong wedge' : ''));
  }
}

function checkDelivery(copies, art, slotLists) {
  const flag = (m) => findings.undeliverable.push(m);
  const sellable = new Map();
  const slotted = new Map();
  for (const [source, items] of copies) {
    for (const [id, it] of Object.entries(items)) {
      if (it.sellable === true) sellable.set(id, [...(sellable.get(id) || []), source]);
      if (typeof it.slot === 'string') {
        const key = `${id}\u0000${it.slot}`;
        slotted.set(key, [...(slotted.get(key) || []), source]);
      }
    }
  }
  for (const [id, sources] of sellable) {
    if (!art.has(id)) {
      flag(`${id} is sellable (${sources.join(', ')}) but has no art in ${FILES.wallet} — the shop would draw the fallback and sell it`);
    }
  }
  for (const [key, sources] of slotted) {
    const [id, slot] = key.split('\u0000');
    for (const [list, slots] of slotLists) {
      if (!slots.has(slot)) flag(`${id}.slot "${slot}" (${sources.join(', ')}) is not in ${list}`);
    }
  }
}

function checkVocabulary(slotLists, names) {
  const flag = (m) => findings.vocabulary.push(m);
  const all = [...new Set(slotLists.flatMap(([, s]) => [...s]))];
  for (const slot of all) {
    const missing = slotLists.filter(([, s]) => !s.has(slot)).map(([list]) => list);
    if (missing.length) flag(`slot "${slot}" is missing from ${missing.join(' and ')}`);
  }
  for (const key of ['items', 'config', 'spinDoc']) {
    const seen = Object.entries(names).map(([layer, n]) => `${layer} "${n[key]}"`);
    if (new Set(Object.values(names).map((n) => n[key])).size > 1) {
      flag(`the ${key} name disagrees — ${seen.join(', ')}; this script reads the server's`);
    }
  }
}

function checkRegression() {
  const gone = [
    [FILES.server, /const STORE_ITEMS = \{/, 'STORE_ITEMS'],
    [FILES.server, /const SPIN_PRIZES = \[/, 'SPIN_PRIZES'],
    [FILES.sample, /static const List<StoreItem> storeItems = \[/, 'SampleData.storeItems'],
    [FILES.client, /static const Map<String, String> _slotOf = \{/, 'CosmeticSlot._slotOf'],
    [FILES.wallet, /static const Set<String> _undeliverable = \{/, '_undeliverable'],
    [FILES.wallet, /static const _prizes = \[/, 'the wheel\'s _prizes face'],
  ];
  for (const [rel, re, what] of gone) {
    if (re.test(read(rel))) findings.regression.push(`${what} is back in ${rel}`);
  }
}

// ── Run ───────────────────────────────────────────────────────────────────

const TITLES = {
  drift: 'DRIFT — Firestore is not what catalogue.json says',
  undeliverable: 'UNDELIVERABLE — sold or equippable, but this build cannot deliver it',
  vocabulary: 'VOCABULARY — the copies kept on purpose disagree',
  regression: 'REGRESSION — a deleted hardcoded copy is back',
};

function printSection(key) {
  if (!findings[key].length) return;
  console.log(`\n  ${TITLES[key]}:`);
  for (const m of findings[key]) console.log(`    ✗ ${m}`);
}

(async () => {
  const local = process.argv.includes('--local');

  // The tripwire runs FIRST and reports at once. The likely way a deleted
  // copy returns is merging a branch cut before it went — which also takes
  // away the declarations the extractors below anchor on. Run afterwards, it
  // would never be reached: the run would stop on "declaration not found"
  // without saying why.
  checkRegression();
  printSection('regression');

  // Everything read out of the tree comes next, so a broken extractor stops
  // the run before anything is fetched.
  const file = sourceFile();
  const art = artIds();
  const slotLists = [
    ['server COSMETIC_SLOTS', quotedList(FILES.server, /const COSMETIC_SLOTS = \[([^\]]*)\];/, 'server COSMETIC_SLOTS')],
    ['client CosmeticSlot.all', clientSlots()],
    ['seed SLOTS', quotedList(FILES.seed, /const SLOTS = \[([^\]]*)\];/, 'seed SLOTS')],
  ];
  const names = collectionNames();
  const serverNames = names.server;

  console.log('\n  catalogue drift check');
  console.log('\n  read:');
  console.log(`    catalogue.json   ${Object.keys(file.items).length} items, prizes [${file.spin.prizes.join(', ')}]`);
  console.log(`    art map          ${art.size} ids — ${[...art].join(', ')}`);
  for (const [list, slots] of slotLists) console.log(`    ${list.padEnd(24)} [${[...slots].join(', ')}]`);

  let live = null;
  if (local) {
    console.log('    Firestore        NOT READ (--local) — drift is not checked');
  } else {
    const target = process.env.FIRESTORE_EMULATOR_HOST
      ? `emulator ${process.env.FIRESTORE_EMULATOR_HOST}`
      : `production ${PROJECT_ID}`;
    live = await readFirestore(serverNames);
    const prizes = live.spin === null ? 'MISSING' : `prizes ${canon(live.spin.prizes, true)}`;
    console.log(`    Firestore        ${target}: ${Object.keys(live.items).length} ${serverNames.items}, ` +
      `${serverNames.config}/${serverNames.spinDoc} ${prizes}`);
    checkDrift(file, live);
  }

  const copies = [['catalogue.json', file.items]];
  if (live) copies.push(['Firestore', live.items]);
  checkDelivery(copies, art, slotLists);
  checkVocabulary(slotLists, names);

  for (const key of ['drift', 'undeliverable', 'vocabulary']) printSection(key);
  const total = Object.values(findings).reduce((n, list) => n + list.length, 0);

  if (total) {
    console.log(`\n  ${total} finding${total === 1 ? '' : 's'}. Exit 1.\n`);
    process.exit(1);
  }
  console.log(local
    ? '\n  ✓ clean against the file. Drift was NOT checked — Firestore was not read.\n'
    : '\n  ✓ clean — Firestore matches catalogue.json, every sellable id has art, and the slot lists agree.\n');
  process.exit(0);
})().catch((e) => die(e.stack || e.message));
