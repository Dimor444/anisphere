import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/user_model.dart';
import '../../shared/widgets/user_avatar.dart';
import 'call_screen.dart';

/// Incoming call UI with Accept / Decline.
///
/// On **Accept**, it swaps its own body for a [CallScreen] (with
/// `autoConnect: true`) on the *same* route — so when that call ends, its
/// duration pops straight back to whoever pushed this screen (the chat).
/// On **Decline**, it pops with `0`.
class IncomingCallScreen extends StatefulWidget {
  final UserModel user;
  final bool video;
  const IncomingCallScreen({super.key, required this.user, this.video = false});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    Haptics.medium();
  }

  void _accept() {
    Haptics.heavy();
    setState(() => _accepted = true);
  }

  void _decline() {
    Haptics.medium();
    Navigator.of(context).pop(0); // 0s → logged as a cancelled/declined call
  }

  @override
  Widget build(BuildContext context) {
    // Once accepted, hand off to the live call (same route → its duration
    // result pops back to the chat).
    if (_accepted) {
      return CallScreen(user: widget.user, video: widget.video, autoConnect: true);
    }

    final name = widget.user.displayName ?? widget.user.username;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            UserAvatar.fromUser(widget.user, radius: 60),
            const SizedBox(height: 24),
            Text(name, style: AppTextStyles.heading.copyWith(color: Colors.white, fontSize: 26)),
            const SizedBox(height: 8),
            Text(
              widget.video ? 'Incoming video call…' : 'Incoming call…',
              style: AppTextStyles.subheading.copyWith(color: Colors.white70, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 48, left: 40, right: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _action(icon: LucideIcons.phoneOff, label: 'Decline', color: AppColors.error, onTap: _decline),
                  _action(icon: widget.video ? LucideIcons.video : LucideIcons.phone, label: 'Accept', color: AppColors.success, onTap: _accept),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}
