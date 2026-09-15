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

  /// Deducts [amount] for [itemId] and returns the new balance.
  ///
  /// Grants nothing — the server records what was bought in the currency
  /// ledger and the item itself is delivered later. Throws
  /// [InsufficientGoldException] when the balance is short; every other
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
      if (e.code == 'failed-precondition' &&
          details is Map &&
          details['reason'] == 'insufficient-funds') {
        throw InsufficientGoldException(
          balance: (details['balance'] as num?)?.toInt() ?? 0,
          required: (details['required'] as num?)?.toInt() ?? amount,
        );
      }
      debugPrint('[CurrencyService] spendGold failed: [${e.code}] ${e.message}');
      rethrow;
    }
  }
}
