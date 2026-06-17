import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synapse_app/core/api/client.dart';
import 'package:synapse_app/core/auth/token_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'synapse_bearer_token': 'test-token',
    });
  });

  SynapseApiClient makeClient(MockClientHandler handler) {
    return SynapseApiClient(
      baseUrl: 'http://localhost:8000',
      tokenStore: TokenStore(),
      httpClient: MockClient(handler),
    );
  }

  group('SynapseApiClient.getAnalyticsTopics', () {
    test(
      'requests topics with supported query params and parses rows',
      () async {
        final client = makeClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/v1/analytics/topics');
          expect(request.url.queryParameters, {'limit': '12'});
          expect(request.headers['Authorization'], 'Bearer test-token');
          return http.Response(
            jsonEncode({
              'data': [
                {'topic_tag': 'launch', 'count': 4, 'avg_consensus': 0.82},
                {'topic_tag': null, 'count': 1, 'avg_consensus': null},
              ],
              'generated_at': '2026-06-09T00:00:00Z',
              'tenant_id': 'tenant-a',
            }),
            200,
          );
        });

        final topics = await client.getAnalyticsTopics(limit: 12);

        expect(topics.topics, hasLength(2));
        expect(topics.topics.first.topicTag, 'launch');
        expect(topics.topics.first.count, 4);
        expect(topics.topics.first.avgConsensus, closeTo(0.82, 0.001));
        expect(topics.topics.last.label, 'Untagged');
        expect(topics.generatedAt, '2026-06-09T00:00:00Z');
        expect(topics.tenantId, 'tenant-a');
      },
    );

    test('preserves cluster response and source metadata', () async {
      final client = makeClient((request) async {
        expect(request.url.path, '/v1/analytics/topics');
        expect(request.url.queryParameters, {'limit': '8', 'cluster': 'true'});
        return http.Response(
          jsonEncode({
            'data': [
              {'topic_tag': 'security', 'count': 3, 'avg_consensus': 0.7},
            ],
            'clusters': 'Security: authentication, compliance',
            'cluster_sources': [
              {'memory_id': 'mem-1', 'score': 0.91},
            ],
          }),
          200,
        );
      });

      final topics = await client.getAnalyticsTopics(cluster: true, limit: 8);

      expect(topics.clusters, contains('Security'));
      expect(topics.clusterSources, hasLength(1));
      expect(topics.clusterSources.single, containsPair('memory_id', 'mem-1'));
    });

    test('surfaces ApiException on backend error', () async {
      final client = makeClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'analytics query failed'}),
          500,
        );
      });

      await expectLater(
        client.getAnalyticsTopics(limit: 12),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.message, 'message', 'analytics query failed'),
        ),
      );
    });
  });
}
