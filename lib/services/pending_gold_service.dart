import 'package:shared_preferences/shared_preferences.dart';

/// Local ledger of AniGold earned from mini-games but not yet credited to the
/// user's account. `users.aniGold` in Firestore is protected by security rules
/// (clients must not write it) — crediting will be done by Cloud Functions
/// later. Until then, game rewards accumulate here.
class PendingGoldService {
  PendingGoldService._();
  static final PendingGoldService instance = PendingGoldService._();

  static const String _key = 'pending_anigold';

  /// Total AniGold earned locally and awaiting server-side credit.
  Future<int> getPending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? 0;
  }

  /// Adds [amount] to the pending ledger and returns the new total.
  Future<int> add(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    final total = (prefs.getInt(_key) ?? 0) + amount;
    await prefs.setInt(_key, total);
    return total;
  }
}
