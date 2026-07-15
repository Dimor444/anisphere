import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/my_list_service.dart';

/// Smoke test against the REAL Firebase project (anisphere-36cb0): proves
/// anonymous auth is enabled and the deployed Firestore rules allow owner
/// access to users/{uid}/myList. Only touches the throwaway guest user it
/// creates (deleted in teardown) and one test doc under it.
const _id = 900000009;

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Drop any stale (e.g. emulator-minted) keychain user so this run proves
    // the real fresh-user path.
    await FirebaseAuth.instance.signOut();
  });

  tearDownAll(() async {
    // Remove the test doc and the throwaway guest account.
    try {
      await MyListService.instance.removeFromMyList(_id);
      await FirebaseAuth.instance.currentUser?.delete();
    } catch (_) {}
  });

  testWidgets('guest button signs in against production', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/signin');

    await pumpUntil(tester, find.text('Continue as Guest'));
    await tester.tap(find.text('Continue as Guest'));

    // Success = snackbar with the uid + navigation to the feed.
    await pumpUntil(tester, find.textContaining('Signed in as guest'));
    final user = AuthService.instance.currentUser;
    expect(user, isNotNull);
    expect(user!.isAnonymous, isTrue);
    expect(find.textContaining(user.uid), findsOneWidget);
  });

  testWidgets('my list CRUD works against production rules', (tester) async {
    final svc = MyListService.instance;

    await svc.addToMyList(_id, 'ZZProd Smoke Test', '', ListStatus.planning);
    expect(await svc.isAnimeInMyList(_id), isTrue);

    await svc.updateAnimeStatus(_id, ListStatus.completed);
    await svc.updateScore(_id, 7);
    final entry = (await svc.watchEntry(_id).first)!;
    expect(entry.status, ListStatus.completed);
    expect(entry.score, 7);

    await svc.removeFromMyList(_id);
    expect(await svc.isAnimeInMyList(_id), isFalse);
  });
}
