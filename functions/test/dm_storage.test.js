/**
 * DM image storage contract (Phase 3), against the Storage + Firestore
 * emulators: proves the split('_')/hasAny participant gate in
 * storage.rules actually works in the Storage rules runtime (it shares
 * the Firestore rules language, but per instruction it is verified here,
 * not assumed), plus size/type caps, immutability, and the blocked-thread
 * image-send denial on the Firestore side.
 *
 * Uids here are underscore-free on purpose — the cid.split('_') gate
 * assumes Firebase-generated uids, which never contain '_'.
 *
 * Run with the emulators up:
 *   node test/dm_storage.test.js
 */

process.env.FIRESTORE_EMULATOR_HOST ||= '127.0.0.1:8080';
process.env.FIREBASE_STORAGE_EMULATOR_HOST ||= '127.0.0.1:9199';

const assert = require('node:assert');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const { ref, uploadBytes, getBytes } = require('firebase/storage');
const { doc, setDoc, updateDoc, collection, serverTimestamp } = require('firebase/firestore');

const [FS_HOST, FS_PORT] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
const [ST_HOST, ST_PORT] = process.env.FIREBASE_STORAGE_EMULATOR_HOST.split(':');

const A = 'userA';
const B = 'userB';
const C = 'userC';
const CID = [A, B].sort().join('_');

const jpegBytes = (size = 64) => new Uint8Array(size).fill(0xd8);
const JPEG = { contentType: 'image/jpeg' };

// Object names are unique per run: the emulator's clearStorage() is a no-op
// on this version, and with immutability (resource == null on create) a
// leftover from an earlier run would poison a fixed-name upload.
const RUN = Date.now();
const uniq = (base) => `${RUN}_${base}`;

async function run(name, fn) {
  await fn();
  console.log(`  ok — ${name}`);
}

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-dm-storage',
    firestore: {
      host: FS_HOST,
      port: Number(FS_PORT),
      rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8'),
    },
    storage: {
      host: ST_HOST,
      port: Number(ST_PORT),
      rules: readFileSync(resolve(__dirname, '../../storage.rules'), 'utf8'),
    },
  });
  const store = (uid) => env.authenticatedContext(uid).storage();
  const db = (uid) => env.authenticatedContext(uid).firestore();
  const img = (s, name = 'pic.jpg') => ref(s, `dm_images/${CID}/${uniq(name)}`);

  await env.clearFirestore();

  await run('participant upload + read allowed (split/hasAny PROVEN in Storage runtime)', async () => {
    await assertSucceeds(uploadBytes(img(store(A)), jpegBytes(), JPEG));
    await assertSucceeds(getBytes(img(store(B))));
    await assertSucceeds(getBytes(img(store(A))));
  });

  await run('2. non-participant cannot read dm_images/{cid}/*', async () => {
    await assertFails(getBytes(img(store(C))));
    // …and cannot upload into someone else's thread either.
    await assertFails(uploadBytes(img(store(C), 'evil.jpg'), jpegBytes(), JPEG));
  });

  await run('3. upload > 1MB rejected', async () => {
    await assertFails(uploadBytes(img(store(A), 'big.jpg'), jpegBytes(1024 * 1024), JPEG));
    // At the cap boundary: strictly-under passes.
    await assertSucceeds(uploadBytes(img(store(A), 'edge.jpg'), jpegBytes(1024 * 1024 - 1), JPEG));
  });

  await run('4. non-JPEG rejected', async () => {
    await assertFails(uploadBytes(img(store(A), 'sneaky.png'), jpegBytes(), { contentType: 'image/png' }));
    await assertFails(uploadBytes(img(store(A), 'file.pdf'), jpegBytes(), { contentType: 'application/pdf' }));
  });

  await run('5. overwrite of an existing image rejected (update: false)', async () => {
    await assertFails(uploadBytes(img(store(A)), jpegBytes(32), JPEG));
    await assertFails(uploadBytes(img(store(B)), jpegBytes(32), JPEG));
  });

  await run('7. blocked conversation rejects image send too (Firestore side)', async () => {
    await assertSucceeds(setDoc(doc(db(A), 'conversations', CID), {
      participants: [A, B].sort(),
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      lastMessage: '',
      lastSenderId: '',
      lastReadAt: {},
      blockedBy: [],
    }));
    const imageMsg = (uid) => setDoc(doc(collection(db(uid), 'conversations', CID, 'messages')), {
      senderId: uid,
      text: '',
      imageUrl: 'https://example.com/pic.jpg',
      createdAt: serverTimestamp(),
    });
    await assertSucceeds(imageMsg(A)); // baseline: image message legal when unblocked
    await assertSucceeds(updateDoc(doc(db(B), 'conversations', CID), { blockedBy: [B] }));
    await assertFails(imageMsg(A));
    await assertFails(imageMsg(B));
    await assertSucceeds(updateDoc(doc(db(B), 'conversations', CID), { blockedBy: [] }));
  });

  await env.cleanup();
  console.log('\nAll DM storage tests passed.');
  process.exit(0);
})().catch((e) => {
  console.error('\nFAILED:', e.message);
  process.exit(1);
});
