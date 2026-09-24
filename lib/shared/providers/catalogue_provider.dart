import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth_service.dart';
import '../../services/currency_service.dart';

// TWO PROVIDERS, NOT ONE. store_items and config/spin_wheel are different
// reads that fail independently, and each has its own consumers: the shop
// and My Items need the items, the wheel needs the prizes. Combined, a
// malformed prize array would blank the shop, a missing store_items would
// lock the wheel, and every catalogue event would rebuild the wheel — with a
// "which half is still loading" state that every consumer would have to
// unpick.
//
// Both are autoDispose and gated on a session, like myInventoryProvider and
// todaySpinProvider, and for the same reason: a keepAlive provider holding a
// Firestore listener across a sign-out has already cost us a
// permission-denied once. The uid is not part of either path here — the
// catalogue is the same for everyone — but firestore.rules admit these reads
// to signed-in users only, so a listener with no session is a listener that
// will be refused.

/// The store catalogue by id, in shop order.
///
/// Null when there is no catalogue to show: offline on a first launch with
/// nothing cached. That is NOT the same as empty — see
/// [CurrencyService.watchCatalogue].
final catalogueProvider =
    StreamProvider.autoDispose<Map<String, CatalogueItem>?>((ref) {
  if (AuthService.instance.uid == null) return Stream.value(null);
  return CurrencyService.instance.watchCatalogue();
});

/// The wheel face, in segment order, or null when there is none to paint.
final spinPrizesProvider = StreamProvider.autoDispose<List<int>?>((ref) {
  if (AuthService.instance.uid == null) return Stream.value(null);
  return CurrencyService.instance.watchSpinPrizes();
});
