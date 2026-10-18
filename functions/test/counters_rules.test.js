/**
 * Client-bumped counters, against the Firestore emulator.
 *
 * Every count a client may move is bumped in the batch that writes the record
 * it counts. Before this change the rules never looked at that record, so any
 * signed-in player could move anyone's follower, following and post counts,
 * any post's or video's likes, an article's saves and a day's vote tally by
 * one per write, without limit. Each count whose record the rules can find is
 * now tied to it with existsAfter: a profile's followerCount to the caller's
 * followers/ entry, likes to the caller's like, saves to the caller's
 * savedNews entry, a tally to the caller's vote for that anime. followingCount
 * and postsCount cannot be tied — their records' ids are not visible from the
 * profile — so only the owner may move them. Comment counts, views and shares
 * are unchanged: a comment's id is generated, and views and shares have no
 * record at all. A hashtag's create and update are limited to what every
 * build writes — the tag as its own name, the count from one and +1, lastUsed
 * the server's clock. A tally's title must be text of at most 200 characters
 * and its cover empty or an AniList cover; neither is pinned.
 *
 * Cases are tagged:
 *   [compat]     the batches installed builds send — must pass under any rules
 *   [unchanged]  refusals both this ruleset and the one before it make
 *   [new rule]   a write the previous rules allowed — must be refused now
 *
 * Every refusal starts from a write that passes and changes one thing.
 *
 * RULES_FILE points the suite at another ruleset, which is how the negative
 * control runs: against the rules before this change, exactly the [new rule]
 * cases must fail (the writes go through) and every other case must pass.
 *
 * Run with the firestore emulator up:
 *   node test/counters_rules.test.js
 *   RULES_FILE=/path/to/old.rules node test/counters_rules.test.js
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
  doc, collection, setDoc, updateDoc, writeBatch, serverTimestamp, increment, Timestamp,
} = require('firebase/firestore');

const [HOST, PORT] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
const RULES = process.env.RULES_FILE || resolve(__dirname, '../../firestore.rules');

const DAY = '2026-10-18';
const FRIEREN = 154587;
// What AniList returns as coverImage.large for Frieren — what the vote screen sends.
const FRIEREN_COVER = 'https://s4.anilist.co/file/anilistcdn/media/anime/cover/large/bx154587-qQTzQnEJJ3oB.jpg';
const OTHER_ANIME = 21;

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

let n = 0;
const id = (prefix) => `${prefix}${String(++n).padStart(6, '0')}`;

(async () => {
  const rules = readFileSync(RULES, 'utf8');
  const env = await initializeTestEnvironment({
    projectId: 'demo-counters-rules',
    firestore: { host: HOST, port: Number(PORT), rules },
  });
  // Each run reuses the same ids, so it starts from nothing.
  await env.clearFirestore();
  // One instance per player: a batch cannot mix documents from two instances.
  const dbs = new Map();
  const as = (uid) => {
    if (!dbs.has(uid)) dbs.set(uid, env.authenticatedContext(uid).firestore());
    return dbs.get(uid);
  };
  const seed = (path, data) => env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), path), data));

  /** A profile, written past the rules. */
  const profile = async (overrides = {}) => {
    const uid = id('user');
    await seed(`users/${uid}`, {
      userId: uid, userName: `anifan_${uid.slice(-6)}`, displayName: 'Anime Fan', isPlus: false,
      followerCount: 5, followingCount: 3, postsCount: 2, ...overrides,
    });
    return uid;
  };
  /** A post or video by [author] with some engagement, written past the rules. */
  const post = async (author) => {
    const p = id('post');
    await seed(`posts/${p}`, { userId: author, content: 'hi', likes: 3, commentsCount: 2, viewCount: 10 });
    return p;
  };
  const video = async (author) => {
    const v = id('video');
    await seed(`ani_videos/${v}`, { userId: author, likes: 3, commentsCount: 2, shareCount: 1, viewCount: 10 });
    return v;
  };
  const news = async () => {
    const a = id('news');
    await seed(`news/${a}`, { title: 'News', views: 5, saves: 2 });
    return a;
  };
  const tally = async (anime) => {
    await seed(`community_votes/${DAY}/tally/${anime}`,
      { anilist_id: anime, animeTitle: 'Frieren', animeCover: '', dayId: DAY, voteCount: 2 });
  };

  // ── The batches installed builds send ────────────────────────────────
  /** FollowService.followUser. */
  const follow = (me, them) => writeBatch(as(me))
    .set(doc(as(me), `users/${me}/following/${them}`), { followedAt: serverTimestamp() })
    .set(doc(as(me), `users/${them}/followers/${me}`), { followedAt: serverTimestamp() })
    .update(doc(as(me), `users/${me}`), { followingCount: increment(1) })
    .update(doc(as(me), `users/${them}`), { followerCount: increment(1) })
    .commit();
  /** FollowService.unfollowUser. */
  const unfollow = (me, them) => writeBatch(as(me))
    .delete(doc(as(me), `users/${me}/following/${them}`))
    .delete(doc(as(me), `users/${them}/followers/${me}`))
    .update(doc(as(me), `users/${me}`), { followingCount: increment(-1) })
    .update(doc(as(me), `users/${them}`), { followerCount: increment(-1) })
    .commit();
  const followed = async (me, them) => {
    await seed(`users/${me}/following/${them}`, { followedAt: Timestamp.now() });
    await seed(`users/${them}/followers/${me}`, { followedAt: Timestamp.now() });
  };
  /** FeedService.createPost, with one hashtag. */
  const createPost = (me, tag = 'frieren') => {
    const ref = doc(collection(as(me), 'posts'));
    return writeBatch(as(me))
      .set(ref, {
        userId: me, userName: 'Anime Fan', userAvatar: '', isVerified: false, content: `hello #${tag}`,
        anilist_id: null, animeTitle: null, animeCover: null, imageUrls: [], hashtags: [tag],
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(), likes: 0, commentsCount: 0, viewCount: 0,
        isSpoiler: false,
      })
      .update(doc(as(me), `users/${me}`), { postsCount: increment(1) })
      .set(doc(as(me), `trending_hashtags/${tag}`),
        { tag, count: increment(1), lastUsed: serverTimestamp() }, { merge: true })
      .commit();
  };
  /** FeedService.deletePost. */
  const deletePost = (me, p) => writeBatch(as(me))
    .delete(doc(as(me), `posts/${p}`))
    .update(doc(as(me), `users/${me}`), { postsCount: increment(-1) })
    .commit();
  /** FeedService.likePost / AniVideoService.likeVideo, and the unlikes. */
  const like = (me, parent, withUid = true) => writeBatch(as(me))
    .set(doc(as(me), `${parent}/likes/${me}`), { likedAt: serverTimestamp(), ...(withUid ? { uid: me } : {}) })
    .update(doc(as(me), parent), { likes: increment(1) })
    .commit();
  const unlike = (me, parent) => writeBatch(as(me))
    .delete(doc(as(me), `${parent}/likes/${me}`))
    .update(doc(as(me), parent), { likes: increment(-1) })
    .commit();
  /** addComment / deleteComment on a post or video. */
  const comment = (me, parent) => writeBatch(as(me))
    .set(doc(collection(as(me), `${parent}/comments`)),
      { userId: me, userName: 'Anime Fan', userAvatar: '', content: 'nice', createdAt: serverTimestamp(), likes: 0 })
    .update(doc(as(me), parent), { commentsCount: increment(1) })
    .commit();
  const deleteComment = async (me, parent, by = me) => {
    const c = id('comment');
    await seed(`${parent}/comments/${c}`, { userId: me, content: 'nice' });
    return writeBatch(as(by))
      .delete(doc(as(by), `${parent}/comments/${c}`))
      .update(doc(as(by), parent), { commentsCount: increment(-1) })
      .commit();
  };
  /** NewsService.saveArticle / unsaveArticle. */
  const save = (me, a) => writeBatch(as(me))
    .set(doc(as(me), `users/${me}/savedNews/${a}`), { savedAt: serverTimestamp() })
    .update(doc(as(me), `news/${a}`), { saves: increment(1) })
    .commit();
  const unsave = (me, a) => writeBatch(as(me))
    .delete(doc(as(me), `users/${me}/savedNews/${a}`))
    .update(doc(as(me), `news/${a}`), { saves: increment(-1) })
    .commit();
  /** CommunityVoteService.castVote: the vote and the tally, in one batch. */
  const vote = (me, slot, anime, tallyAnime = anime, { title = 'Frieren', cover = '' } = {}) => writeBatch(as(me))
    .set(doc(as(me), `community_votes/${DAY}/votes/${me}_${slot}`), {
      userId: me, anilist_id: anime, animeTitle: title, animeCover: cover, dayId: DAY, voteSlot: slot,
      votedAt: serverTimestamp(),
    })
    .set(doc(as(me), `community_votes/${DAY}/tally/${tallyAnime}`), {
      anilist_id: tallyAnime, animeTitle: title, animeCover: cover, dayId: DAY, voteCount: increment(1),
    }, { merge: true })
    .commit();

  console.log(`counters rules — ${process.env.RULES_FILE ? `RULES_FILE=${RULES}` : 'current rules'}`);

  // ── Installed builds keep working ─────────────────────────────────────
  await run('[compat]', 'follow', async () => assertSucceeds(follow(await profile(), await profile())));
  await run('[compat]', 'unfollow', async () => {
    const me = await profile(); const them = await profile();
    await followed(me, them);
    await assertSucceeds(unfollow(me, them));
  });
  await run('[compat]', 'create a post with a hashtag', async () => assertSucceeds(createPost(await profile())));
  await run('[compat]', "a second post with a hashtag already in use", async () => {
    const tag = id('tag');
    await seed(`trending_hashtags/${tag}`, { tag, count: 4, lastUsed: Timestamp.now() });
    await assertSucceeds(createPost(await profile(), tag));
  });
  await run('[compat]', 'a hashtag planted with another tag value: the next post rewrites it', async () => {
    const tag = id('tag');
    await seed(`trending_hashtags/${tag}`, { tag: 'someone-else', count: 4, lastUsed: Timestamp.now() });
    await assertSucceeds(createPost(await profile(), tag));
  });
  await run('[compat]', 'delete a post', async () => {
    const me = await profile();
    await assertSucceeds(deletePost(me, await post(me)));
  });
  await run('[compat]', 'like a post', async () => assertSucceeds(like(await profile(), `posts/${await post(await profile())}`)));
  await run('[compat]', 'like your own post (no uid)', async () => {
    const me = await profile();
    await assertSucceeds(like(me, `posts/${await post(me)}`, false));
  });
  await run('[compat]', 'unlike a post', async () => {
    const me = await profile(); const p = `posts/${await post(await profile())}`;
    await seed(`${p}/likes/${me}`, { likedAt: Timestamp.now(), uid: me });
    await assertSucceeds(unlike(me, p));
  });
  await run('[compat]', 'comment on a post', async () => assertSucceeds(comment(await profile(), `posts/${await post(await profile())}`)));
  await run('[compat]', 'delete your comment', async () => {
    const me = await profile();
    await assertSucceeds(deleteComment(me, `posts/${await post(await profile())}`));
  });
  await run('[compat]', "the post's author deletes someone's comment", async () => {
    const author = await profile();
    await assertSucceeds(deleteComment(await profile(), `posts/${await post(author)}`, author));
  });
  await run('[compat]', 'a post view', async () => {
    const p = await post(await profile());
    await assertSucceeds(updateDoc(doc(as(await profile()), `posts/${p}`), { viewCount: increment(1) }));
  });
  await run('[compat]', 'like a video', async () => assertSucceeds(like(await profile(), `ani_videos/${await video(await profile())}`)));
  await run('[compat]', "a September build's video like: likedAt only", async () =>
    assertSucceeds(like(await profile(), `ani_videos/${await video(await profile())}`, false)));
  await run('[compat]', 'unlike a video', async () => {
    const me = await profile(); const v = `ani_videos/${await video(await profile())}`;
    await seed(`${v}/likes/${me}`, { likedAt: Timestamp.now(), uid: me });
    await assertSucceeds(unlike(me, v));
  });
  await run('[compat]', 'comment on a video', async () => assertSucceeds(comment(await profile(), `ani_videos/${await video(await profile())}`)));
  await run('[compat]', 'delete your video comment', async () => {
    const me = await profile();
    await assertSucceeds(deleteComment(me, `ani_videos/${await video(await profile())}`));
  });
  await run('[compat]', 'a video share and a video view', async () => {
    const v = await video(await profile()); const me = await profile();
    await assertSucceeds(updateDoc(doc(as(me), `ani_videos/${v}`), { shareCount: increment(1) }));
    await assertSucceeds(updateDoc(doc(as(me), `ani_videos/${v}`), { viewCount: increment(1) }));
  });
  await run('[compat]', 'save an article', async () => assertSucceeds(save(await profile(), await news())));
  await run('[compat]', 'unsave an article', async () => {
    const me = await profile(); const a = await news();
    await seed(`users/${me}/savedNews/${a}`, { savedAt: Timestamp.now() });
    await assertSucceeds(unsave(me, a));
  });
  await run('[compat]', 'an article view', async () =>
    assertSucceeds(updateDoc(doc(as(await profile()), `news/${await news()}`), { views: increment(1) })));
  await run('[compat]', "the day's first vote for an anime creates its tally", async () =>
    assertSucceeds(vote(await profile(), 1, 1000 + n)));
  await run('[compat]', 'a vote adds to an existing tally', async () => {
    await tally(FRIEREN);
    await assertSucceeds(vote(await profile(), 1, FRIEREN));
  });
  await run('[compat]', "a vote carrying AniList's large cover, creating the tally", async () =>
    assertSucceeds(vote(await profile(), 1, 2000 + n, undefined, { title: 'Frieren: Beyond Journey’s End', cover: FRIEREN_COVER })));
  await run('[compat]', 'a later vote carrying an edited title and a new cover', async () => {
    await tally(FRIEREN);
    await assertSucceeds(vote(await profile(), 1, FRIEREN, FRIEREN,
      { title: 'Frieren: Beyond Journey’s End', cover: FRIEREN_COVER }));
  });
  await run('[compat]', "a Plus player's second vote (slot 2)", async () => {
    const me = await profile({ isPlus: true });
    await seed(`community_votes/${DAY}/votes/${me}_1`, { userId: me, anilist_id: OTHER_ANIME, dayId: DAY, voteSlot: 1 });
    await tally(FRIEREN);
    await assertSucceeds(vote(me, 2, FRIEREN));
  });

  // ── Refused before and after ──────────────────────────────────────────
  await run('[unchanged]', 'followerCount set outright', async () => {
    const them = await profile();
    await assertFails(updateDoc(doc(as(await profile()), `users/${them}`), { followerCount: 1000 }));
  });
  await run('[unchanged]', 'a follow that adds two followers', async () => {
    const me = await profile(); const them = await profile();
    await assertFails(writeBatch(as(me))
      .set(doc(as(me), `users/${them}/followers/${me}`), { followedAt: serverTimestamp() })
      .update(doc(as(me), `users/${them}`), { followerCount: increment(2) })
      .commit());
  });
  await run('[unchanged]', 'a like that adds two', async () => {
    const me = await profile(); const p = `posts/${await post(await profile())}`;
    await assertFails(writeBatch(as(me))
      .set(doc(as(me), `${p}/likes/${me}`), { likedAt: serverTimestamp(), uid: me })
      .update(doc(as(me), p), { likes: increment(2) })
      .commit());
  });
  await run('[unchanged]', 'a view taken back', async () => {
    const p = await post(await profile());
    await assertFails(updateDoc(doc(as(await profile()), `posts/${p}`), { viewCount: increment(-1) }));
  });
  await run('[unchanged]', 'a tally that jumps by two', async () => {
    await tally(FRIEREN);
    const me = await profile();
    await assertFails(writeBatch(as(me))
      .set(doc(as(me), `community_votes/${DAY}/votes/${me}_1`),
        { userId: me, anilist_id: FRIEREN, dayId: DAY, voteSlot: 1, votedAt: serverTimestamp() })
      .update(doc(as(me), `community_votes/${DAY}/tally/${FRIEREN}`), { voteCount: increment(2) })
      .commit());
  });

  // ── A count moved without the record it counts ────────────────────────
  await run('[new rule]', "a stranger adds a follower to someone's count", async () => {
    const them = await profile();
    await assertFails(updateDoc(doc(as(await profile()), `users/${them}`), { followerCount: increment(1) }));
  });
  await run('[new rule]', "a stranger takes a follower off someone's count", async () => {
    const them = await profile();
    await assertFails(updateDoc(doc(as(await profile()), `users/${them}`), { followerCount: increment(-1) }));
  });
  await run('[new rule]', "a follower bumps the count again with an entry already there", async () => {
    const me = await profile(); const them = await profile();
    await followed(me, them);
    await assertFails(updateDoc(doc(as(me), `users/${them}`), { followerCount: increment(1) }));
  });
  await run('[new rule]', "a stranger moves someone's followingCount", async () => {
    const them = await profile();
    await assertFails(updateDoc(doc(as(await profile()), `users/${them}`), { followingCount: increment(1) }));
  });
  await run('[new rule]', "a stranger moves someone's postsCount", async () => {
    const them = await profile();
    await assertFails(updateDoc(doc(as(await profile()), `users/${them}`), { postsCount: increment(-1) }));
  });
  await run('[new rule]', 'post likes +1 with no like', async () => {
    const p = await post(await profile());
    await assertFails(updateDoc(doc(as(await profile()), `posts/${p}`), { likes: increment(1) }));
  });
  await run('[new rule]', 'post likes -1 with no like to remove (a double unlike)', async () => {
    const p = `posts/${await post(await profile())}`;
    await assertFails(unlike(await profile(), p));
  });
  await run('[new rule]', 'video likes +1 with no like', async () => {
    const v = await video(await profile());
    await assertFails(updateDoc(doc(as(await profile()), `ani_videos/${v}`), { likes: increment(1) }));
  });
  await run('[new rule]', 'article saves +1 with no save', async () => {
    const a = await news();
    await assertFails(updateDoc(doc(as(await profile()), `news/${a}`), { saves: increment(1) }));
  });
  await run('[new rule]', 'a tally +1 with no vote', async () => {
    await tally(FRIEREN);
    await assertFails(updateDoc(doc(as(await profile()), `community_votes/${DAY}/tally/${FRIEREN}`), { voteCount: increment(1) }));
  });
  await run('[new rule]', 'a tally created with no vote', async () => {
    const anime = 5000 + n;
    await assertFails(setDoc(doc(as(await profile()), `community_votes/${DAY}/tally/${anime}`),
      { anilist_id: anime, animeTitle: 'X', animeCover: '', dayId: DAY, voteCount: 1 }));
  });
  await run('[new rule]', "a vote for one anime adding to another's tally", async () => {
    await tally(FRIEREN);
    await assertFails(vote(await profile(), 1, OTHER_ANIME, FRIEREN));
  });

  // ── A hashtag update carrying more than every build writes ────────────
  const hashtag = async () => {
    const tag = id('tag');
    await seed(`trending_hashtags/${tag}`, { tag, count: 4, lastUsed: Timestamp.now() });
    return tag;
  };
  const bumpTag = async (tag, extra) => updateDoc(doc(as(await profile()), `trending_hashtags/${tag}`),
    { tag, count: increment(1), lastUsed: serverTimestamp(), ...extra });
  await run('[unchanged]', 'a hashtag that jumps by two', async () =>
    assertFails(bumpTag(await hashtag(), { count: increment(2) })));
  await run('[new rule]', 'a hashtag +1 carrying another field', async () =>
    assertFails(bumpTag(await hashtag(), { featured: true })));
  await run('[new rule]', 'a hashtag +1 that renames its tag', async () =>
    assertFails(bumpTag(await hashtag(), { tag: 'renamed' })));
  await run('[new rule]', 'a hashtag +1 dated in the future', async () =>
    assertFails(bumpTag(await hashtag(), { lastUsed: Timestamp.fromMillis(Date.now() + 86400000) })));
  const newTag = async (extra) => {
    const tag = id('tag');
    return setDoc(doc(as(await profile()), `trending_hashtags/${tag}`),
      { tag, count: 1, lastUsed: serverTimestamp(), ...extra });
  };
  await run('[new rule]', 'a hashtag created with another field', async () => assertFails(newTag({ featured: true })));
  await run('[new rule]', 'a hashtag created under another name', async () => assertFails(newTag({ tag: 'other' })));
  await run('[new rule]', 'a hashtag created dated in the future', async () =>
    assertFails(newTag({ lastUsed: Timestamp.fromMillis(Date.now() + 86400000) })));

  // ── A tally's title and cover: AniList's, or refused ──────────────────
  const voteOnTally = async (display) => {
    await tally(FRIEREN);
    return vote(await profile(), 1, FRIEREN, FRIEREN, display);
  };
  await run('[new rule]', 'a tally title of 201 characters', async () => assertFails(voteOnTally({ title: 'x'.repeat(201) })));
  await run('[new rule]', 'a tally title that is not text', async () => assertFails(voteOnTally({ title: 42 })));
  await run('[new rule]', 'a tally cover on another host', async () =>
    assertFails(voteOnTally({ cover: 'https://evil.example/file/anilistcdn/media/anime/cover/large/bx1.jpg' })));
  await run('[new rule]', 'a tally cover that is an AniList avatar, not a cover', async () =>
    assertFails(voteOnTally({ cover: 'https://s4.anilist.co/file/anilistcdn/user/avatar/large/b5055-x.png' })));
  await run('[new rule]', 'a tally created with a cover on another host', async () =>
    assertFails(vote(await profile(), 1, 3000 + n, undefined, { cover: 'https://evil.example/c.jpg' })));

  await env.cleanup();

  const failed = results.filter((r) => !r.ok);
  const count = (t) => {
    const all = results.filter((r) => r.tag === t);
    return `${t} ${all.filter((r) => r.ok).length}/${all.length}`;
  };
  console.log(`\n${results.length - failed.length}/${results.length} passed — ` +
    ['[compat]', '[unchanged]', '[new rule]'].map(count).join(', '));
  process.exit(failed.length ? 1 : 0);
})().catch((e) => {
  console.error('\nSUITE ERROR:', e.message);
  process.exit(2);
});
