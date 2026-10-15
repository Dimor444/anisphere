import 'package:anisphere/widgets/anime_challenge_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, double rating) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 160,
          height: 220,
          child: AnimeChallengeCard(animeName: 'Frieren', genre: 'Adventure', rating: rating),
        ),
      ),
    ));
  }

  // The card looks its cover up over the network the moment it builds; in a
  // test that lookup never answers, so each case unmounts the card and runs
  // the clock past the lookup's timeouts before it ends.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets('an unscored search result shows no star and no 0.0', (tester) async {
    await pumpCard(tester, 0);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.text('0.0'), findsNothing);
    await settle(tester);
  });

  testWidgets('a scored one shows its rating', (tester) async {
    await pumpCard(tester, 8.7);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(find.text('8.7'), findsOneWidget);
    await settle(tester);
  });
}
