import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synapse_app/core/api/client.dart';
import 'package:synapse_app/core/auth/token_store.dart';
import 'package:synapse_app/features/memory/memory_screen.dart';

SynapseApiClient _client(MockClientHandler handler) {
  return SynapseApiClient(
    baseUrl: 'http://localhost:8000',
    tokenStore: TokenStore(),
    httpClient: MockClient(handler),
  );
}

Widget _wrap(SynapseApiClient client) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 1200, child: MemoryScreen(apiClient: client)),
    ),
  );
}

Finder _tab(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is Tab && widget.text == label,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'synapse_bearer_token': 'test-token',
    });
  });

  testWidgets('tabs render', (tester) async {
    final client = _client((_) async => http.Response('{}', 200));

    await tester.pumpWidget(_wrap(client));

    expect(_tab('Search'), findsOneWidget);
    expect(_tab('Reflect'), findsOneWidget);
    expect(_tab('Retain'), findsOneWidget);
    expect(_tab('Graph'), findsOneWidget);
    expect(_tab('Compile'), findsOneWidget);
  });

  testWidgets('invalid metadata JSON shows validation error', (tester) async {
    final client = _client((_) async => http.Response('{}', 200));

    await tester.pumpWidget(_wrap(client));
    await tester.tap(_tab('Retain'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Content'),
      'Remember this',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Metadata JSON (optional)'),
      '{bad',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Retain'));
    await tester.pumpAndSettle();

    expect(find.text('Metadata must be valid JSON object.'), findsOneWidget);
  });

  testWidgets('retain success shows memory ID', (tester) async {
    final client = _client((request) async {
      expect(request.url.path, '/v1/memory/retain');
      return http.Response(
        jsonEncode({'memory_id': 'mem-retained', 'stored': true}),
        201,
      );
    });

    await tester.pumpWidget(_wrap(client));
    await tester.tap(_tab('Retain'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Content'),
      'Remember this',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Retain'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.textContaining('mem-retained'), findsOneWidget);
  });

  testWidgets('reflect answer renders', (tester) async {
    final client = _client((request) async {
      expect(request.url.path, '/v1/memory/reflect');
      return http.Response(
        jsonEncode({'answer': 'Use the launch checklist.', 'sources': []}),
        200,
      );
    });

    await tester.pumpWidget(_wrap(client));
    await tester.tap(_tab('Reflect'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Question'),
      'What now?',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Reflect'));
    await tester.pumpAndSettle();

    expect(find.text('Use the launch checklist.'), findsOneWidget);
  });

  testWidgets('graph search results render', (tester) async {
    final client = _client((request) async {
      expect(request.url.path, '/v1/memory/graph/search');
      return http.Response(
        jsonEncode({
          'query': 'Launch',
          'bank': 'decisions',
          'count': 1,
          'entities': [
            {
              'entity_id': 'ent-1',
              'name': 'Launch plan',
              'entity_type': 'topic',
              'metadata': {},
            },
          ],
        }),
        200,
      );
    });

    await tester.pumpWidget(_wrap(client));
    await tester.tap(_tab('Graph'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Entity query'),
      'Launch',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.text('Launch plan'), findsOneWidget);
    expect(find.textContaining('ent-1'), findsOneWidget);
  });
}
