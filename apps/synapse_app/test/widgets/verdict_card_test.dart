import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synapse_app/widgets/verdict_card.dart';

void main() {
  group('VerdictCard', () {
    Widget wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

    testWidgets('shows verdict text', (tester) async {
      await tester.pumpWidget(
        wrap(const VerdictCard(verdict: 'The council recommends option A.')),
      );
      expect(
        find.text('The council recommends option A.', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('renders markdown formatting without raw markers', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const VerdictCard(verdict: '**Recommended Names:**\n\n1. Misty')),
      );

      expect(
        find.textContaining('**Recommended', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('Recommended Names:', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Misty', findRichText: true), findsOneWidget);
    });

    testWidgets('shows confidence label chip', (tester) async {
      await tester.pumpWidget(
        wrap(
          const VerdictCard(verdict: 'Some verdict', confidenceLabel: 'High'),
        ),
      );
      expect(find.text('High'), findsOneWidget);
    });

    testWidgets('shows consensus bar when score provided', (tester) async {
      await tester.pumpWidget(
        wrap(const VerdictCard(verdict: 'Some verdict', consensusScore: 0.85)),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('85%'), findsOneWidget);
    });

    testWidgets('shows dissent warning when dissentDetected is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const VerdictCard(verdict: 'Some verdict', dissentDetected: true)),
      );
      expect(find.text('Dissent detected'), findsOneWidget);
    });

    testWidgets('does not show dissent warning when dissentDetected is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const VerdictCard(verdict: 'Some verdict', dissentDetected: false),
        ),
      );
      expect(find.text('Dissent detected'), findsNothing);
    });
  });
}
