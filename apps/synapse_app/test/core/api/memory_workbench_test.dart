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

  Map<String, dynamic> hit() => {
    'memory_id': 'mem-1',
    'content': 'Keep the launch checklist short.',
    'score': 0.91,
    'bank_id': 'decisions',
    'tags': ['launch'],
    'metadata': {'source': 'test'},
  };

  test('searchMemory parses hits with metadata', () async {
    final client = makeClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/memory/search');
      expect(request.url.queryParameters['q'], 'launch');
      expect(request.url.queryParameters['bank'], 'decisions');
      return http.Response(
        jsonEncode({
          'query': 'launch',
          'bank': 'decisions',
          'count': 1,
          'hits': [hit()],
        }),
        200,
      );
    });

    final hits = await client.searchMemory('launch');

    expect(hits, hasLength(1));
    expect(hits.single.memoryId, 'mem-1');
    expect(hits.single.metadata, {'source': 'test'});
  });

  test(
    'retainMemory sends content/tags/metadata and parses response',
    () async {
      Map<String, dynamic>? captured;
      final client = makeClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/memory/retain');
        captured = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'memory_id': 'mem-retained', 'stored': true}),
          201,
        );
      });

      final response = await client.retainMemory(
        content: 'Remember this.',
        tags: ['manual'],
        metadata: {'source': 'widget'},
      );

      expect(captured, {
        'content': 'Remember this.',
        'bank_id': 'agents',
        'tags': ['manual'],
        'metadata': {'source': 'widget'},
      });
      expect(response.memoryId, 'mem-retained');
      expect(response.stored, isTrue);
    },
  );

  test(
    'reflectMemory sends query/bank/include_sources and parses answer',
    () async {
      Map<String, dynamic>? captured;
      final client = makeClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/memory/reflect');
        captured = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'answer': 'Use the short launch checklist.',
            'sources': [hit()],
          }),
          200,
        );
      });

      final reflection = await client.reflectMemory(
        query: 'What should we do?',
        bankId: 'precedents',
        includeSources: false,
        maxTokens: 500,
      );

      expect(captured, {
        'query': 'What should we do?',
        'bank_id': 'precedents',
        'include_sources': false,
        'max_tokens': 500,
      });
      expect(reflection.answer, 'Use the short launch checklist.');
      expect(reflection.sources, hasLength(1));
    },
  );

  test('forgetMemory sends memory_ids and tags', () async {
    Map<String, dynamic>? captured;
    final client = makeClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/memory/forget');
      captured = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'ok': true, 'deleted': 2}), 200);
    });

    final response = await client.forgetMemory(
      memoryIds: ['mem-1'],
      tags: ['draft'],
    );

    expect(captured, {
      'bank_id': 'agents',
      'memory_ids': ['mem-1'],
      'tags': ['draft'],
    });
    expect(response['deleted'], 2);
  });

  test('graphSearchMemory parses entities', () async {
    final client = makeClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/memory/graph/search');
      return http.Response(
        jsonEncode({
          'query': 'Launch',
          'bank': 'decisions',
          'count': 1,
          'entities': [
            {
              'entity_id': 'ent-1',
              'name': 'Launch',
              'entity_type': 'topic',
              'metadata': {'weight': 3},
            },
          ],
        }),
        200,
      );
    });

    final response = await client.graphSearchMemory(
      query: 'Launch',
      bankId: 'decisions',
    );

    expect(response.entities.single.entityId, 'ent-1');
    expect(response.entities.single.metadata, {'weight': 3});
  });

  test('graphNeighborsMemory parses hits', () async {
    Map<String, dynamic>? captured;
    final client = makeClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/memory/graph/neighbors');
      captured = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'bank': 'agents',
          'count': 1,
          'hits': [hit()],
        }),
        200,
      );
    });

    final response = await client.graphNeighborsMemory(
      entityIds: ['ent-1'],
      bankId: 'agents',
      maxDepth: 2,
      limit: 20,
    );

    expect(captured, {
      'entity_ids': ['ent-1'],
      'bank_id': 'agents',
      'max_depth': 2,
      'limit': 20,
    });
    expect(response.hits.single.memoryId, 'mem-1');
  });

  test('compileMemory sends bank/scope and preserves response', () async {
    Map<String, dynamic>? captured;
    final client = makeClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/memory/compile');
      captured = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({'ok': true, 'bank_id': 'decisions'}),
        202,
      );
    });

    final response = await client.compileMemory(
      bankId: 'decisions',
      scope: {'topic': 'launch'},
    );

    expect(captured!['bank_id'], 'decisions');
    expect(jsonDecode(captured!['scope'] as String), {'topic': 'launch'});
    expect(response, {'ok': true, 'bank_id': 'decisions'});
  });
}
