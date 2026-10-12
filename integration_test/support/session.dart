// Session setup shared by the integration tests that sign users in.

import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/follow_service.dart';

/// Signs out and mints a new guest, returning its uid.
///
/// `signOut()` then `initAuth()` used to do this. Since the deliberate
/// sign-out flag, `initAuth()` refuses after a sign-out instead of minting —
/// a stray service call must never hand a signed-out user a new identity — so
/// the fresh user comes from `signInAsGuest()`, the one sanctioned mint.
Future<String> freshGuest() async {
  await AuthService.instance.signOut();
  return (await AuthService.instance.signInAsGuest()).uid;
}

/// Gives the signed-in user a profile and a claimed handle, and returns the
/// handle.
///
/// Any test that drives the shell needs this: every new guest gets the claim
/// gate, a modal sheet that covers the screen and swallows the test's taps.
/// [prefix] gets a per-run suffix because the emulator keeps claims for as
/// long as it runs; keep it to 14 characters so the handle stays legal.
Future<String> claimTestHandle(String prefix) async {
  await FollowService.instance.ensureProfile();
  final handle = '$prefix${DateTime.now().millisecondsSinceEpoch % 1000000}';
  await FollowService.instance.claimUserName(handle);
  return handle;
}
