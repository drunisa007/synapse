import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synapse_app/core/api/client.dart';
import 'package:synapse_app/core/auth/token_store.dart';
import 'package:synapse_app/features/analytics/analytics_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'synapse_bearer_token': 'test-token',
    });
  });

  SynapseApiClient makeClient({
    Map<String, dynamic>? topicsBody,
    int topicsStatus = 200,
    List<Uri>? capturedRequests,
  }) {
    return SynapseApiClient(
      baseUrl: 'http://localhost:8000',
      tokenStore: TokenStore(),
      httpClient: MockClient((request) async {
        capturedRequests?.add(request.url);
        switch (request.url.path) {
          case '/v1/analytics/consensus':
            return http.Response(
              jsonEncode({
                'data': {
                  'high': 1,
                  'medium': 1,
                  'low': 0,
                  'unscored': 0,
                  'total': 2,
                },
              }),
              200,
            );
          case '/v1/analytics/velocity':
            return http.Response(
              jsonEncode({
                'data': [
                  {'date': '2026-06-08', 'count': 1},
                  {'date': '2026-06-09', 'count': 2},
                ],
              }),
              200,
            );
          case '/v1/analytics/members':
            return http.Response(
              jsonEncode({
                'data': [
                  {
                    'member_id': 'architect',
                    'member_name': 'Systems Architect',
                    'councils_participated': 2,
                    'avg_consensus_score': 0.8,
                    'dissent_count': 0,
                  },
                ],
              }),
              200,
            );
          case '/v1/analytics/topics':
            return http.Response(
              jsonEncode(
                topicsBody ??
                    {
                      'data': [
                        {
                          'topic_tag': 'launch',
                          'count': 4,
                          'avg_consensus': 0.8,
                        },
                        {
                          'topic_tag': 'security',
                          'count': 2,
                          'avg_consensus': 0.75,
                        },
                      ],
                    },
              ),
              topicsStatus,
            );
          default:
            return http.Response('not found', 404);
        }
      }),
    );
  }

  Widget wrap(SynapseApiClient client) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 900,
          child: AnalyticsScreen(apiClient: client),
        ),
      ),
    );
  }

  testWidgets('topics section renders topic rows', (tester) async {
    await tester.pumpWidget(wrap(makeClient()));
    await tester.pumpAndSettle();

    expect(find.text('Topics'), findsOneWidget);
    expect(find.text('launch'), findsOneWidget);
    expect(find.text('security'), findsOneWidget);
    expect(find.textContaining('4 councils'), findsOneWidget);
    expect(find.text('Consensus distribution'), findsOneWidget);
    expect(find.text('Top members'), findsOneWidget);
  });

  testWidgets('empty topic state renders', (tester) async {
    final client = makeClient(topicsBody: {'data': []});

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('No topic data yet'), findsOneWidget);
  });

  testWidgets('topic failure does not hide existing analytics', (tester) async {
    final client = makeClient(
      topicsStatus: 500,
      topicsBody: {'detail': 'analytics query failed'},
    );

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Could not load topics'), findsOneWidget);
    expect(find.text('Consensus distribution'), findsOneWidget);
    expect(find.text('Top members'), findsOneWidget);
  });

  testWidgets('cluster toggle reloads topics with cluster query', (
    tester,
  ) async {
    final captured = <Uri>[];
    final client = makeClient(
      capturedRequests: captured,
      topicsBody: {
        'data': [
          {'topic_tag': 'security', 'count': 3, 'avg_consensus': 0.7},
        ],
        'clusters': 'Security: authentication and compliance',
        'cluster_sources': [
          {'memory_id': 'mem-1'},
        ],
      },
    );

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clusters'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Security: authentication'), findsOneWidget);
    expect(
      captured.where(
        (uri) =>
            uri.path == '/v1/analytics/topics' &&
            uri.queryParameters['cluster'] == 'true' &&
            uri.queryParameters['limit'] == '12',
      ),
      isNotEmpty,
    );
  });
}
