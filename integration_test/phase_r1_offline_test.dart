import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/core/theme/app_theme.dart';
import 'package:anisphere/features/profile/claim_username_sheet.dart';
import 'package:anisphere/firebase_options.dart';

/// Fix R1 verification: Firestore pointed at a CLOSED port (deterministic
/// unavailability — auth emulator still up so the uid resolves). The claim
/// sheet's availability check must fail legibly, the error-only "Later"
/// button must appear and free the app. Emulator/localhost only.
Future<void> pumpUntil(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 40)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// Minimal host: opens the claim sheet over a tappable page, like the shell
/// gate does — without needing the gate check (which would fail open here).
class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int taps = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => showClaimUserNameSheet(context, suggested: ''));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => setState(() => taps++),
          child: Text('host tapped $taps'),
        ),
      ),
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    // CLOSED port — every Firestore read fails with unavailable.
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 65123);
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
    await FirebaseAuth.instance.signInAnonymously();
  });

  testWidgets('offline gate: legible error, Later frees the app', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: AppTheme.dark, home: const _Host()),
    ));
    await pumpUntil(tester, find.text('Claim your username'));

    // No Later button before the check errs.
    expect(find.text('Not now — you can claim later'), findsNothing);

    await tester.enterText(find.byType(TextField), 'perfectlyfinehandle');
    // Availability check hits the dead port -> legible error state.
    await pumpUntil(tester, find.text('Couldn\'t check — try again'));
    await binding.takeScreenshot('r1_offline_error_with_later');

    // Claim stays disabled, but Later is visible and tappable.
    final later = find.text('Not now — you can claim later');
    expect(later, findsOneWidget);
    await tester.tap(later);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Claim your username'), findsNothing, reason: 'Later pops the sheet');

    // The app underneath is usable again.
    await tester.tap(find.textContaining('host tapped'));
    await tester.pump();
    expect(find.text('host tapped 1'), findsOneWidget);
    await binding.takeScreenshot('r1_offline_freed');
  });
}
