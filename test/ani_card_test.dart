import 'package:anisphere/data/models/user.dart';
import 'package:anisphere/features/profile/widgets/ani_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const player = UserData(id: 'u1', userName: 'mira_k', displayName: 'Mira', countryCode: 'TR');

  Future<void> pumpCard(WidgetTester tester, {UserData? me = player, int? completed, bool pending = false}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AniCard(player: me, completed: completed, completedPending: pending)),
      ));

  testWidgets("prints the player's own handle, flag and completed count", (tester) async {
    await pumpCard(tester, completed: 12);
    expect(find.text('@mira_k'), findsOneWidget);
    expect(find.text('🇹🇷'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('none of the sample user is left', (tester) async {
    await pumpCard(tester, completed: 12);
    for (final gone in ['KazeNoYuki', '347', '4.8K', '4,821', '1203h', '1,203h', '#847', 'Eps', 'Watched', 'Rank']) {
      expect(find.textContaining(gone), findsNothing, reason: gone);
    }
  });

  testWidgets('no count, no stat — never a stand-in number', (tester) async {
    await pumpCard(tester);
    expect(find.text('Completed'), findsNothing);
  });

  testWidgets('while counting, the stat holds a placeholder', (tester) async {
    await pumpCard(tester, pending: true);
    expect(find.text('…'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('a guest before claiming shows the reserved placeholder, and no country no flag', (tester) async {
    await pumpCard(tester, me: const UserData(id: 'u1', userName: 'anifan_ab12cd', countryCode: 'XX'), completed: 0);
    expect(find.text('@anifan_ab12cd'), findsOneWidget);
    expect(find.textContaining(RegExp('[\u{1F1E6}-\u{1F1FF}]', unicode: true)), findsNothing);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('no identity yet, no one on the card', (tester) async {
    await pumpCard(tester, me: null, completed: 3);
    expect(find.textContaining('@'), findsNothing);
  });
}
