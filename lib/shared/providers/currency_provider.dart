import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/sample_data.dart';

class CurrencyState {
  final int gold;
  final int gem;
  final int streak;
  const CurrencyState({required this.gold, required this.gem, required this.streak});

  CurrencyState copyWith({int? gold, int? gem, int? streak}) => CurrencyState(
        gold: gold ?? this.gold,
        gem: gem ?? this.gem,
        streak: streak ?? this.streak,
      );
}

class CurrencyController extends StateNotifier<CurrencyState> {
  CurrencyController()
      : super(CurrencyState(
          gold: SampleData.mainUser.aniGold,
          gem: SampleData.mainUser.aniGem,
          streak: SampleData.mainUser.streak,
        ));

  void addGold(int n) => state = state.copyWith(gold: state.gold + n);
  void addGem(int n) => state = state.copyWith(gem: state.gem + n);

  /// Spend AniGold. Returns false (and changes nothing) if balance too low.
  bool spendGold(int n) {
    if (state.gold < n) return false;
    state = state.copyWith(gold: state.gold - n);
    return true;
  }

  bool spendGem(int n) {
    if (state.gem < n) return false;
    state = state.copyWith(gem: state.gem - n);
    return true;
  }

  void restoreStreak() => state = state.copyWith(streak: state.streak);
}

final currencyProvider =
    StateNotifierProvider<CurrencyController, CurrencyState>(
        (ref) => CurrencyController());
