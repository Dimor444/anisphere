import 'package:flutter/material.dart';

import 'profile_screen.dart';

/// Thin alias kept for the True Fan integration tests that construct this
/// widget directly; the implementation is the unified [ProfileScreen].
/// New code should use the `/profile/:userId` route instead.
class UserProfileScreen extends StatelessWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) => ProfileScreen(userId: userId);
}
