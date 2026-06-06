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

  group('SynapseApiClient.listCouncils', () {
    test('parses council list response correctly', () async {
      final client = makeClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        return http.Response(
          jsonEncode([
            {
              'session_id': 'abc-123',
              'question': 'Should we expand to new markets?',
              'status': 'closed',
              'council_type': 'llm',
              'consensus_score': 0.87,
              'confidence_label': 'High',
              'created_at': '2026-04-01T10:00:00Z',
              'closed_at': '2026-04-01T11:00:00Z',
              'conflict_detected': false,
            },
          ]),
          200,
        );
      });

      final councils = await client.listCouncils();
      expect(councils.length, 1);
      expect(councils[0].sessionId, 'abc-123');
      expect(councils[0].question, 'Should we expand to new markets?');
      expect(councils[0].status, 'closed');
      expect(councils[0].consensusScore, closeTo(0.87, 0.001));
      expect(councils[0].conflictDetected, isFalse);
    });
  });

  group('SynapseApiClient.createCouncil', () {
    test('sends correct JSON body', () async {
      String? capturedBody;
      final client = makeClient((request) async {
        capturedBody = request.body;
        return http.Response(
          jsonEncode({
            'session_id': 'new-session',
            'thread_id': 'thread-1',
            'status': 'pending',
          }),
          200,
        );
      });

      await client.createCouncil(
        question: 'What is the best strategy?',
        councilType: 'llm',
        templateId: 'tpl-1',
      );

      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['question'], 'What is the best strategy?');
      expect(body['council_type'], 'llm');
      expect(body['template_id'], 'tpl-1');
    });
  });

  // ── Cerebro envelope unwrapping ──────────────────────────────────────────

  group('SynapseApiClient isCerebro — list unwrapping', () {
    test('listCouncils unwraps {"data": [...]} envelope', () async {
      final client = makeClient((request) async {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'session_id': 'cerebro-1',
                'question': 'Cerebro council?',
                'status': 'pending',
                'council_type': 'llm',
                'created_at': '2026-04-01T10:00:00Z',
                'conflict_detected': false,
              },
            ],
          }),
          200,
        );
      });
      client.isCerebro = true;

      final councils = await client.listCouncils();
      expect(councils.length, 1);
      expect(councils[0].sessionId, 'cerebro-1');
    });

    test('listCouncils still works with bare Synapse array', () async {
      final client = makeClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'session_id': 'synapse-1',
              'question': 'Synapse council?',
              'status': 'pending',
              'council_type': 'llm',
              'created_at': '2026-04-01T10:00:00Z',
              'conflict_detected': false,
            },
          ]),
          200,
        );
      });
      // isCerebro defaults to false — bare array must still parse

      final councils = await client.listCouncils();
      expect(councils.length, 1);
      expect(councils[0].sessionId, 'synapse-1');
    });
  });

  group('SynapseApiClient isCerebro — object unwrapping', () {
    test('getCouncil unwraps {"data": {...}} envelope', () async {
      final client = makeClient((request) async {
        return http.Response(
          jsonEncode({
            'data': {
              'session_id': 'cerebro-2',
              'question': 'Wrapped council?',
              'status': 'closed',
              'council_type': 'llm',
              'created_at': '2026-04-01T10:00:00Z',
              'conflict_detected': false,
              'dissent_detected': false,
              'contributions_received': 3,
              'members': [],
            },
          }),
          200,
        );
      });
      client.isCerebro = true;

      final council = await client.getCouncil('cerebro-2');
      expect(council.sessionId, 'cerebro-2');
      expect(council.status, 'closed');
    });

    test('createCouncil unwraps {"data": {...}} envelope', () async {
      final client = makeClient((request) async {
        return http.Response(
          jsonEncode({
            'data': {
              'session_id': 'new-cerebro',
              'thread_id': 'thread-cerebro',
              'status': 'pending',
            },
          }),
          201,
        );
      });
      client.isCerebro = true;

      final result = await client.createCouncil(question: 'New question?');
      expect(result.sessionId, 'new-cerebro');
      expect(result.threadId, 'thread-cerebro');
    });
  });

  group('SynapseApiClient isCerebro — nested object unwrapping', () {
    test('listDeviceTokens unwraps {"data": {"devices": [...]}}', () async {
      final client = makeClient((request) async {
        return http.Response(
          jsonEncode({
            'data': {
              'devices': [
                {
                  'id': 'dev-1',
                  'token_type': 'ntfy',
                  'token': 'abc123',
                  'created_at': '2026-04-01T10:00:00Z',
                },
              ],
            },
          }),
          200,
        );
      });
      client.isCerebro = true;

      final tokens = await client.listDeviceTokens();
      expect(tokens.length, 1);
      expect(tokens[0].id, 'dev-1');
    });
  });

  group('SynapseApiClient.listEvents', () {
    test('unwraps Synapse {events: [...]} thread history envelope', () async {
      final client = makeClient((request) async {
        expect(request.url.path, '/v1/threads/thread-1/events');
        return http.Response(
          jsonEncode({
            'thread_id': 'thread-1',
            'events': [
              {
                'id': 7,
                'thread_id': 'thread-1',
                'event_type': 'verdict',
                'actor_id': 'system',
                'actor_name': '',
                'content': 'done',
                'metadata': {'confidence_label': 'high'},
                'created_at': '2026-04-01T10:00:00Z',
              },
            ],
            'count': 1,
          }),
          200,
        );
      });

      final events = await client.listEvents('thread-1');
      expect(events.length, 1);
      expect(events.single.eventType, 'verdict');
      expect(events.single.content, 'done');
    });
  });

  group('SynapseApiClient error handling', () {
    test('throws ApiException on 401', () async {
      final client = makeClient((request) async {
        return http.Response(jsonEncode({'detail': 'Unauthorized'}), 401);
      });

      expect(
        () => client.listCouncils(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('ApiException contains message from response body', () async {
      final client = makeClient((request) async {
        return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
      });

      try {
        await client.listCouncils();
        fail('Expected ApiException');
      } on ApiException catch (e) {
        expect(e.message, 'Token expired');
        expect(e.statusCode, 401);
      }
    });
  });
}
