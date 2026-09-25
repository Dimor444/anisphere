import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// The spend was refused because the balance is too low.
///
/// A distinct type because it is the one refusal that is not a fault: nothing
/// broke, the user simply cannot afford this. The UI has to say how short they
/// are rather than offer a retry that cannot succeed — the same shape
/// [UploadCapExceededException] gives the upload cap.
class InsufficientGoldException implements Exception {
  final int balance;
  final int required;
  const InsufficientGoldException({required this.balance, required this.required});

  int get short => required - balance;

  @override
  String toString() =>
      'InsufficientGoldException(balance: $balance, required: $required)';
}

/// The spend was refused because the item is already owned.
///
/// Items are one-time, and the inventory document is keyed by item id, so
/// owning one twice is not representable. Distinct from a fault for the same
/// reason as [InsufficientGoldException]: nothing broke, and a retry cannot
/// succeed — the right UI is to show the item as owned.
class AlreadyOwnedException implements Exception {
  final String itemId;
  const AlreadyOwnedException(this.itemId);

  @override
  String toString() => 'AlreadyOwnedException($itemId)';
}

/// The server will not sell this item — it is held back, withdrawn, or not in
/// the catalogue at all.
///
/// Reachable without a bug, two ways: builds from before the catalogue moved
/// carry their own copy of the store list, and this one renders a CACHED read
/// of store_items that can be a moment behind the server. Either can offer
/// something since pulled. That is a "no longer available", not a "try
/// again".
class ItemUnavailableException implements Exception {
  final String itemId;

  /// 'coming-soon', 'withdrawn', or 'unknown' when the server does not know
  /// the id at all.
  final String unavailable;
  const ItemUnavailableException(this.itemId, this.unavailable);

  @override
  String toString() => 'ItemUnavailableException($itemId, $unavailable)';
}

/// The price the shop displayed is not the price the server holds.
///
/// The server refuses rather than charging its own number, so the user is
/// never billed something other than what they were shown. Carries the real
/// price so the UI can say what it is now.
///
/// With one catalogue this no longer means two hand-kept tables disagreeing.
/// It means the shop rendered a cached read of store_items that the server
/// has since moved past — which is exactly when the check earns its keep.
class PriceChangedException implements Exception {
  final String itemId;
  final int price;
  final int offered;
  const PriceChangedException(
      {required this.itemId, required this.price, required this.offered});

  @override
  String toString() =>
      'PriceChangedException($itemId: shop said $offered, server says $price)';
}

/// Today's spin is already used.
///
/// Carries when the next one opens, so the UI can say "come back at" rather
/// than only "no".
class AlreadySpunException implements Exception {
  final DateTime nextSpinAt;

  /// What the earlier spin paid, when the server still has it.
  final int? prize;
  const AlreadySpunException({required this.nextSpinAt, this.prize});

  @override
  String toString() => 'AlreadySpunException(next: $nextSpinAt)';
}

/// The outcome of a spin, decided entirely by the server.
class SpinResult {
  /// Index into the wheel face — what the client rotates to.
  final int segment;

  /// Gold actually credited. Authoritative even when the painted face is a
  /// cached read of config/spin_wheel older than the one the server drew
  /// from.
  final int prize;
  final int balance;
  final DateTime nextSpinAt;
  const SpinResult({
    required this.segment,
    required this.prize,
    required this.balance,
    required this.nextSpinAt,
  });
}

/// A daily task was claimed before it was done — or it looked done here, and
/// the server's proof disagreed.
///
/// The bar counts likes this device can see; the server counts only posts
/// that still exist and are not the claimer's own. The two disagree when a
/// liked post was deleted since, so this carries the server's breakdown
/// rather than a bare "no".
class TaskNotCompleteException implements Exception {
  final int counted;
  final int target;
  final int ownPosts;
  final int deletedPosts;
  const TaskNotCompleteException({
    required this.counted,
    required this.target,
    required this.ownPosts,
    required this.deletedPosts,
  });

  @override
  String toString() => 'TaskNotCompleteException($counted/$target, own $ownPosts, deleted $deletedPosts)';
}

/// Today's claim for this task is already paid.
class TaskAlreadyClaimedException implements Exception {
  final DateTime nextClaimAt;
  const TaskAlreadyClaimedException(this.nextClaimAt);

  @override
  String toString() => 'TaskAlreadyClaimedException(next: $nextClaimAt)';
}

/// A paid claim, as the server reports it.
class TaskClaim {
  final String taskId;
  final int reward;
  final int balance;
  const TaskClaim({required this.taskId, required this.reward, required this.balance});
}

/// One row of config/daily_tasks: what a task pays and how much of it is
/// needed. Which tasks EXIST is the server's to say (TASK_VERIFIERS); the
/// wallet draws only the ones it knows how to measure.
class DailyTask {
  final String id;
  final int reward;
  final int target;
  const DailyTask({required this.id, required this.reward, required this.target});

  /// Null when the row is malformed — dropped, not drawn with guesses, for
  /// the reason CatalogueItem.fromDoc gives.
  static DailyTask? fromMap(String id, Object? d) {
    if (d is! Map) return null;
    final reward = d['reward'];
    final target = d['target'];
    if (reward is! int || reward <= 0 || target is! int || target <= 0) return null;
    return DailyTask(id: id, reward: reward, target: target);
  }
}

/// The equip was refused because the item is not owned.
///
/// Distinct from a fault for the same reason as the others: the answer is to
/// buy it, not to retry.
class NotOwnedException implements Exception {
  final String itemId;
  final String slot;
  const NotOwnedException(this.itemId, this.slot);

  @override
  String toString() => 'NotOwnedException($itemId in $slot)';
}

/// Cosmetic slots the server recognises. Mirrors COSMETIC_SLOTS in
/// functions/index.js.
///
/// VOCABULARY, and deliberately not read from the catalogue. WHICH slot an
/// item occupies is catalogue data and lives on [CatalogueItem.slot]; which
/// slots EXIST is decided by code, because each one needs a renderer in this
/// app and a branch in equipCosmetic before it means anything. That makes
/// this list a twin of the server's rather than a copy of the catalogue —
/// the same class as the UTC day-id, enforced by each layer independently.
class CosmeticSlot {
  CosmeticSlot._();
  static const String frame = 'frame';
  static const String postBorder = 'postBorder';
  static const String nameEffect = 'nameEffect';

  /// Slots in the order they are presented.
  static const List<String> all = [frame, postBorder, nameEffect];

  static String label(String slot) => switch (slot) {
        frame => 'Avatar frame',
        postBorder => 'Post border',
        nameEffect => 'Name effect',
        _ => slot,
      };
}

/// One row of store_items: what an item is called, what it costs, and
/// whether it can be bought.
///
/// Art is NOT here. Emoji and gradient ship in the app keyed by [id], because
/// the renderer ships in the app too.
class CatalogueItem {
  /// The document id, and the itemId spendGold is called with.
  final String id;
  final String name;
  final String sub;
  final int price;
  final bool sellable;

  /// The cosmetic slot this item occupies, or null when it is not a cosmetic.
  final String? slot;

  /// Why it cannot be bought — `coming-soon` or `withdrawn` — when
  /// [sellable] is false.
  final String? unavailable;

  /// Shop position. Stored rather than implied by id, so reordering the shop
  /// is a catalogue edit and not a rename.
  final int order;

  const CatalogueItem({
    required this.id,
    required this.name,
    required this.sub,
    required this.price,
    required this.sellable,
    required this.slot,
    required this.unavailable,
    required this.order,
  });

  /// Parses one document, or returns null when it is malformed.
  ///
  /// A malformed row is DROPPED rather than rendered with guesses. The seed
  /// validates every row before writing, so this is only reachable through a
  /// hand edit in the console — and the server would refuse to sell that row
  /// anyway, as `internal`. Offering it here would invite a purchase that is
  /// certain to fail.
  static CatalogueItem? fromDoc(String id, Map<String, dynamic> d) {
    final name = d['name'];
    final sub = d['sub'];
    final price = d['price'];
    final sellable = d['sellable'];
    final slot = d['slot'];
    final unavailable = d['unavailable'];
    final order = d['order'];
    if (name is! String || sub is! String) return null;
    if (price is! int || price <= 0) return null;
    if (sellable is! bool) return null;
    if (slot != null && slot is! String) return null;
    if (unavailable != null && unavailable is! String) return null;
    return CatalogueItem(
      id: id,
      name: name,
      sub: sub,
      price: price,
      sellable: sellable,
      slot: slot as String?,
      unavailable: unavailable as String?,
      // Missing order sorts last rather than dropping the row: position is
      // cosmetic, and a row that is otherwise valid can still be sold.
      order: order is int ? order : 1 << 30,
    );
  }
}

/// Spending AniGold.
///
/// There is no earn path here and no local balance. The balance lives on
/// `users/{uid}.aniGold`, which the client may only read (firestore.rules
/// admits it on no create and no update), so every movement goes through a
/// callable and comes back as a fact rather than a local guess.
class CurrencyService {
  CurrencyService._();
  static final CurrencyService instance = CurrencyService._();

  /// Region spendGold is deployed to. `FirebaseFunctions.instance` defaults to
  /// us-central1, where it does not exist — an unregioned call fails NOT_FOUND
  /// rather than falling back.
  static const String _functionsRegion = 'europe-west1';

  /// Where the catalogue lives. The same three names as functions/index.js,
  /// and read the same way: no bundled fallback, because a fallback would
  /// turn a missing or partial seed into a shop that silently disagrees with
  /// the server charging for it.
  static const String _storeItemsCollection = 'store_items';
  static const String _configCollection = 'config';
  static const String _spinConfigDoc = 'spin_wheel';
  static const String _dailyTasksDoc = 'daily_tasks';
  static const String _taskClaims = 'task_claims';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// The store catalogue by id, in shop order — or null when there is no
  /// catalogue to show.
  ///
  /// NULL IS NOT EMPTY. An empty result that came from the local cache means
  /// "nothing cached and no server answer yet" — a first launch offline —
  /// and rendering that as an empty shop would say the shop sells nothing. An
  /// empty result from the SERVER is a real, empty catalogue and stays empty.
  ///
  /// `includeMetadataChanges` is what lets those two be told apart. Without
  /// it, a cache answer followed by an identical server answer raises no
  /// second event, and an unseeded catalogue seen offline first would stay
  /// "unavailable" forever instead of becoming "empty".
  ///
  /// The map is built in [CatalogueItem.order], and Dart map literals keep
  /// insertion order, so `values` IS the shop's order.
  Stream<Map<String, CatalogueItem>?> watchCatalogue() => _db
          .collection(_storeItemsCollection)
          .snapshots(includeMetadataChanges: true)
          .map((snap) {
        if (snap.docs.isEmpty && snap.metadata.isFromCache) return null;
        final rows = <CatalogueItem>[];
        for (final d in snap.docs) {
          final item = CatalogueItem.fromDoc(d.id, d.data());
          if (item == null) {
            debugPrint('[CurrencyService] store_items/${d.id} is malformed — not offered');
            continue;
          }
          rows.add(item);
        }
        rows.sort((a, b) {
          final byOrder = a.order.compareTo(b.order);
          return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
        });
        return {for (final r in rows) r.id: r};
      });

  /// The wheel face, in segment order — or null when there is none to paint.
  ///
  /// ORDER IS LOAD-BEARING: spinWheel returns an index into the array it read
  /// inside its transaction, and the wheel rotates to that index on this one.
  /// They are the same document, so they agree except for the moment a cached
  /// face is older than the server's; the dialog reports the server's prize,
  /// never the number under the pointer, so that moment cannot misstate a
  /// payout.
  ///
  /// Null covers every "cannot paint" case alike — not cached while offline,
  /// not configured, or malformed — because the wheel does the same thing
  /// for all three, and a spin would fail in all three.
  Stream<List<int>?> watchSpinPrizes() => _db
          .collection(_configCollection)
          .doc(_spinConfigDoc)
          .snapshots()
          .map((snap) {
        if (!snap.exists) {
          debugPrint(snap.metadata.isFromCache
              ? '[CurrencyService] no cached prize wheel — offline?'
              : '[CurrencyService] $_configCollection/$_spinConfigDoc does not exist');
          return null;
        }
        final raw = snap.data()?['prizes'];
        if (raw is! List || raw.isEmpty || raw.any((p) => p is! int || p <= 0)) {
          debugPrint('[CurrencyService] $_configCollection/$_spinConfigDoc.prizes is malformed');
          return null;
        }
        return List<int>.unmodifiable(raw.cast<int>());
      });

  /// Item ids [uid] owns, live.
  ///
  /// The ids ARE the document ids — the inventory is keyed by item, which is
  /// what makes ownership self-deduplicating — so this never reads a field.
  /// A set, because the only question any caller asks is membership.
  Stream<Set<String>> watchOwnedItemIds(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('inventory')
      .snapshots()
      .map((snap) => snap.docs.map((d) => d.id).toSet());

  /// Sets the cosmetic shown in [slot], or clears it when [itemId] is null.
  ///
  /// The server checks ownership and that the item belongs in the slot; the
  /// client cannot be trusted with either. Nothing is written locally — the
  /// new value arrives on users/{uid} and reaches the UI through myIdentity,
  /// the same way the balance does.
  Future<void> equip({required String slot, String? itemId}) async {
    try {
      await FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('equipCosmetic')
          .call<Object?>({'slot': slot, 'itemId': itemId});
      debugPrint('[CurrencyService] equipped ${itemId ?? '(nothing)'} in $slot');
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      if (e.code == 'failed-precondition' &&
          details is Map &&
          details['reason'] == 'not-owned') {
        throw NotOwnedException(itemId ?? '', slot);
      }
      debugPrint('[CurrencyService] equip failed: [${e.code}] ${e.message}');
      rethrow;
    }
  }

  /// Takes today's free spin.
  ///
  /// The server draws, credits and records in one transaction — the client
  /// sends nothing but the request, which is what makes this the one earn
  /// path that needs no claim verified. Throws [AlreadySpunException] when
  /// the day is used.
  Future<SpinResult> spinWheel() async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('spinWheel')
          .call<Object?>(<String, Object?>{});
      final d = result.data;
      if (d is! Map) throw StateError('spinWheel returned $d');
      final r = SpinResult(
        segment: (d['segment'] as num).toInt(),
        prize: (d['prize'] as num).toInt(),
        balance: (d['balance'] as num).toInt(),
        nextSpinAt: DateTime.parse(d['nextSpinAt'] as String),
      );
      debugPrint('[CurrencyService] spin: segment ${r.segment}, +${r.prize} '
          '— balance now ${r.balance}');
      return r;
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      if (e.code == 'failed-precondition' &&
          details is Map &&
          details['reason'] == 'already-spun') {
        throw AlreadySpunException(
          nextSpinAt: DateTime.parse(details['nextSpinAt'] as String),
          prize: (details['prize'] as num?)?.toInt(),
        );
      }
      debugPrint('[CurrencyService] spinWheel failed: [${e.code}] ${e.message}');
      rethrow;
    }
  }

  /// Today's spin record, or null when it has not been taken.
  ///
  /// The id is derived the same way the server derives it, from the UTC day,
  /// so this reads exactly the document spinWheel would write. A stream
  /// rather than a one-shot: the record appears the moment the transaction
  /// commits, so the wheel locks itself without the screen re-reading.
  Stream<DateTime?> watchTodaySpin(String uid) {
    final day = _utcDayId();
    return _db.collection('spins').doc('${uid}_$day').snapshots().map(
          (snap) => snap.exists ? _nextUtcMidnight() : null,
        );
  }

  /// Midnight UTC today — the boundary the server's utcDayId uses, so a day
  /// here is the same day there.
  static DateTime _startOfUtcDay() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  static String _utcDayId() => _startOfUtcDay().toIso8601String().substring(0, 10);

  static DateTime _nextUtcMidnight() => _startOfUtcDay().add(const Duration(days: 1));

  // ── Daily tasks ───────────────────────────────────────────────────────────

  /// config/daily_tasks by task id, or null when there is nothing to show —
  /// missing, not cached while offline, or malformed throughout.
  Stream<Map<String, DailyTask>?> watchDailyTasks() => _db
          .collection(_configCollection)
          .doc(_dailyTasksDoc)
          .snapshots()
          .map((snap) {
        final data = snap.data();
        if (!snap.exists || data == null) return null;
        final tasks = <String, DailyTask>{};
        for (final e in data.entries) {
          final t = DailyTask.fromMap(e.key, e.value);
          if (t == null) {
            debugPrint('[CurrencyService] $_configCollection/$_dailyTasksDoc.${e.key} is malformed — not shown');
            continue;
          }
          tasks[t.id] = t;
        }
        return tasks;
      });

  /// Posts [uid] has liked today, up to [target] — the progress bar's number.
  ///
  /// DISPLAY ONLY. It cannot see that a liked post was deleted since, and the
  /// server re-proves everything when the task is claimed. It does exclude
  /// the user's own posts, because this client never puts `uid` on a like of
  /// its own post (FeedService.likePost), so those never match.
  ///
  /// Capped at [target] documents: past the target the bar is full, and
  /// every document beyond it would be a read that changes nothing on screen.
  /// Video likes share the collection name and are filtered by path, as the
  /// server does.
  Stream<int> watchReactionsToday(String uid, int target) => _db
      .collectionGroup('likes')
      .where('uid', isEqualTo: uid)
      .where('likedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfUtcDay()))
      .limit(target)
      .snapshots()
      .map((snap) => snap.docs.where((d) => d.reference.parent.parent?.parent.id == 'posts').length);

  /// Whether today's [taskId] claim is already paid. The record's id is the
  /// server's own {uid}_{day}_{taskId}, so this reads exactly what
  /// claimDailyTask writes.
  Stream<bool> watchTaskClaimed(String uid, String taskId) => _db
      .collection(_taskClaims)
      .doc('${uid}_${_utcDayId()}_$taskId')
      .snapshots()
      .map((snap) => snap.exists);

  /// Claims today's [taskId]. The server proves the task was done and pays,
  /// in one transaction; nothing is credited here.
  Future<TaskClaim> claimDailyTask(String taskId) async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('claimDailyTask')
          .call<Object?>({'taskId': taskId});
      final d = result.data;
      if (d is! Map) throw StateError('claimDailyTask returned $d');
      final claim = TaskClaim(
        taskId: d['taskId'] as String,
        reward: (d['reward'] as num).toInt(),
        balance: (d['balance'] as num).toInt(),
      );
      debugPrint('[CurrencyService] claimed $taskId: +${claim.reward} — balance now ${claim.balance}');
      return claim;
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      if (e.code == 'failed-precondition' && details is Map) {
        switch (details['reason']) {
          case 'not-complete':
            throw TaskNotCompleteException(
              counted: (details['counted'] as num?)?.toInt() ?? 0,
              target: (details['target'] as num?)?.toInt() ?? 0,
              ownPosts: (details['ownPosts'] as num?)?.toInt() ?? 0,
              deletedPosts: (details['deletedPosts'] as num?)?.toInt() ?? 0,
            );
          case 'already-claimed':
            throw TaskAlreadyClaimedException(DateTime.parse(details['nextClaimAt'] as String));
        }
      }
      debugPrint('[CurrencyService] claimDailyTask failed: [${e.code}] ${e.message}');
      rethrow;
    }
  }

  /// Deducts [amount] for [itemId] and returns the new balance.
  ///
  /// The server deducts, grants the item and writes the ledger receipt in one
  /// transaction, so a success means all three happened.
  ///
  /// [amount] is sent as the price this client DISPLAYED, not as an
  /// instruction: the server charges its own catalogue price and refuses a
  /// disagreement with [PriceChangedException] rather than billing a number
  /// the user was never shown.
  ///
  /// Throws [InsufficientGoldException] when the balance is short,
  /// [AlreadyOwnedException] when the item is already held, and
  /// [ItemUnavailableException] when the server will not sell it. Every other
  /// failure rethrows as-is, because a refusal the user can act on and a
  /// fault they cannot must not look the same.
  ///
  /// NOT safe to call twice for one intent: the function is deliberately not
  /// idempotent, so a double call spends twice exactly as two taps would.
  /// Callers must hold their own in-flight guard.
  Future<int> spendGold({required String itemId, required int amount}) async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('spendGold')
          .call<Object?>({'itemId': itemId, 'amount': amount});
      final data = result.data;
      final balance = data is Map ? (data['balance'] as num?)?.toInt() : null;
      if (balance == null) {
        throw StateError('spendGold returned no balance: $data');
      }
      debugPrint('[CurrencyService] spent $amount on $itemId — balance now $balance');
      return balance;
    } on FirebaseFunctionsException catch (e) {
      // The function answers a short balance with failed-precondition and a
      // `reason` in details. Matching on reason rather than the message keeps
      // this from breaking when the copy changes, and keeps a future
      // failed-precondition for some other cause from being mistaken for it.
      final details = e.details;
      if (e.code == 'failed-precondition' && details is Map) {
        switch (details['reason']) {
          case 'insufficient-funds':
            throw InsufficientGoldException(
              balance: (details['balance'] as num?)?.toInt() ?? 0,
              required: (details['required'] as num?)?.toInt() ?? amount,
            );
          case 'already-owned':
            throw AlreadyOwnedException(itemId);
          case 'not-for-sale':
            throw ItemUnavailableException(
              itemId, (details['unavailable'] as String?) ?? 'unknown');
          case 'unknown-item':
            // Folded in with not-for-sale on purpose: to a user there is no
            // difference between "we pulled this" and "we have never heard of
            // it", and both mean the same thing — it cannot be bought.
            throw ItemUnavailableException(itemId, 'unknown');
          case 'price-mismatch':
            throw PriceChangedException(
              itemId: itemId,
              price: (details['price'] as num?)?.toInt() ?? 0,
              offered: (details['offered'] as num?)?.toInt() ?? amount,
            );
        }
      }
      debugPrint('[CurrencyService] spendGold failed: [${e.code}] ${e.message}');
      rethrow;
    }
  }
}
