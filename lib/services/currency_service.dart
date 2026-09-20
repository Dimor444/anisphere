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
/// Reachable without a bug: a shipped build carries its own copy of the store
/// list, so a client one release behind can offer something the server has
/// since pulled. That is a "no longer available", not a "try again".
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
/// functions/index.js; `nameEffect` has no renderer yet.
class CosmeticSlot {
  CosmeticSlot._();
  static const String frame = 'frame';
  static const String postBorder = 'postBorder';
  static const String nameEffect = 'nameEffect';
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

  FirebaseFirestore get _db => FirebaseFirestore.instance;

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
