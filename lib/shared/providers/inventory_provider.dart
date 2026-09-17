import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth_service.dart';
import '../../services/currency_service.dart';

/// Item ids the signed-in user owns.
///
/// A SIBLING of myIdentityProvider rather than part of it: that one streams
/// the users/{uid} DOCUMENT, and ownership lives in a subcollection beneath
/// it, which a document snapshot cannot carry. Rather than denormalise a list
/// of owned ids onto the profile — a second place for ownership to be wrong —
/// this reads the subcollection that already is the answer. There is still
/// exactly one source of truth per fact: the balance on the doc, ownership in
/// inventory/.
///
/// Gated on there being an identity, and autoDispose, for the reason a
/// keepAlive provider holding a Firestore listener has already cost us once:
/// after a sign-out it keeps querying a path the signed-out client may not
/// read. Null uid subscribes to nothing.
final myInventoryProvider = StreamProvider.autoDispose<Set<String>>((ref) {
  final uid = AuthService.instance.uid;
  if (uid == null) return Stream.value(const <String>{});
  return CurrencyService.instance.watchOwnedItemIds(uid);
});

/// Owned ids, or empty while they load.
///
/// Empty-on-loading is the safe default here: it renders an owned item as
/// buyable for a moment, and the server refuses that with `already-owned`.
/// The opposite default would render a buyable item as owned and hide a
/// purchase the user can actually make.
Set<String> ownedItemIds(WidgetRef ref) =>
    ref.watch(myInventoryProvider).asData?.value ?? const <String>{};
