import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/user_model.dart';
import '../../data/sample_data.dart';

class UserController extends StateNotifier<UserModel> {
  UserController() : super(SampleData.mainUser);

  void togglePlus() => state = state.copyWith(isPlusUser: !state.isPlusUser);

  void setBio(String bio) => state = state.copyWith(bio: bio);

  void setVerified(bool v) => state = state.copyWith(isVerified: v);
}

final userProvider =
    StateNotifierProvider<UserController, UserModel>((ref) => UserController());

/// Convenience: is the active user an AniPlus subscriber?
final isPlusProvider = Provider<bool>((ref) => ref.watch(userProvider).isPlusUser);
