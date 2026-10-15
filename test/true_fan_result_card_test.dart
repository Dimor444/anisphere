import 'package:anisphere/data/models/user.dart';
import 'package:anisphere/widgets/true_fan_result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const player = UserData(id: 'u1', userName: 'mira_k', displayName: 'Mira', countryCode: 'TR');

  Future<void> pumpCard(WidgetTester tester,
      {int score = 8, int? rank, bool rankPending = false, UserData? me = player}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TrueFanResultCard(
            animeName: 'Frieren',
            coverUrl: null,
            score: score,
            timeSeconds: 41.3,
            rank: rank,
            rankPending: rankPending,
            player: me,
          ),
        ),
      ),
    ));
  }

  testWidgets("prints the player's own handle and flag, and nobody else's", (tester) async {
    await pumpCard(tester, rank: 3);
    expect(find.text('@mira_k'), findsOneWidget);
    expect(find.text('🇹🇷'), findsOneWidget);
    expect(find.textContaining('KazeNoYuki'), findsNothing);
    expect(find.text('🇯🇵'), findsNothing);
  });

  testWidgets('a counted rank prints as that rank', (tester) async {
    await pumpCard(tester, rank: 3);
    expect(find.text('#3'), findsOneWidget);
    expect(find.text('WORLD RANK'), findsOneWidget);
  });

  testWidgets('no rank, no rank line — never a stand-in number', (tester) async {
    await pumpCard(tester);
    expect(find.text('WORLD RANK'), findsNothing);
    expect(find.textContaining(RegExp(r'#\d')), findsNothing); // the footer's #AniSphere is not a rank
  });

  testWidgets('while the rank is counted its tile holds a placeholder', (tester) async {
    await pumpCard(tester, rankPending: true);
    expect(find.text('WORLD RANK'), findsOneWidget);
    expect(find.text('…'), findsOneWidget);
  });

  testWidgets('the unknown country marker prints no flag', (tester) async {
    await pumpCard(tester, rank: 3, me: const UserData(id: 'u1', userName: 'anifan_ab12cd', countryCode: 'XX'));
    expect(find.text('@anifan_ab12cd'), findsOneWidget);
    expect(find.textContaining(RegExp('[\u{1F1E6}-\u{1F1FF}]', unicode: true)), findsNothing);
  });

  testWidgets('a pass says it proved their fandom', (tester) async {
    await pumpCard(tester, score: 7);
    expect(find.text('PROVED THEIR FANDOM FOR'), findsOneWidget);
  });

  testWidgets('a run that did not pass says what it was, and claims nothing', (tester) async {
    await pumpCard(tester, score: 2);
    expect(find.text('TOOK THE TRUE FAN CHALLENGE FOR'), findsOneWidget);
    expect(find.textContaining('PROVED'), findsNothing);
  });

  test('the share text claims a pass only for a pass', () {
    expect(TrueFanResultCard.shareText('Frieren', 7), contains('proved'));
    final failed = TrueFanResultCard.shareText('Frieren', 2);
    expect(failed, isNot(contains('proved')));
    expect(failed, contains('2/10'));
  });

  testWidgets('no identity yet, no player row', (tester) async {
    await pumpCard(tester, rank: 3, me: null);
    expect(find.textContaining('@'), findsNothing);
  });
}
