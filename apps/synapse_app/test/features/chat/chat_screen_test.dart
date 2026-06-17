import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synapse_app/core/api/client.dart';
import 'package:synapse_app/core/auth/token_store.dart';
import 'package:synapse_app/features/chat/chat_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'synapse_bearer_token': 'test-token',
    });
  });

  SynapseApiClient makeClient() {
    return SynapseApiClient(
      baseUrl: 'http://localhost:8000',
      tokenStore: TokenStore(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/v1/threads/thread-1/events') {
          return http.Response(
            jsonEncode({
              'thread_id': 'thread-1',
              'events': [
                {
                  'id': 1,
                  'thread_id': 'thread-1',
                  'event_type': 'council_started',
                  'actor_id': 'system',
                  'actor_name': '',
                  'content': 'Council started',
                  'metadata': {
                    'question': 'Suggest cat names for a calm gray cat.',
                    'member_count': 3,
                  },
                  'created_at': '2026-06-09T10:00:00Z',
                },
                {
                  'id': 2,
                  'thread_id': 'thread-1',
                  'event_type': 'member_response',
                  'actor_id': 'm1',
                  'actor_name': 'Naming Expert',
                  'content': '**Misty** is the strongest option.',
                  'metadata': {'model': 'openai/gpt-4o-mini'},
                  'created_at': '2026-06-09T10:00:01Z',
                },
                {
                  'id': 3,
                  'thread_id': 'thread-1',
                  'event_type': 'verdict',
                  'actor_id': 'system',
                  'actor_name': '',
                  'content': '**Recommended Names:**\n\n1. Misty\n2. Luna',
                  'metadata': {
                    'confidence_label': 'high',
                    'consensus_score': 1.0,
                  },
                  'created_at': '2026-06-09T10:00:02Z',
                },
              ],
              'count': 3,
            }),
            200,
          );
        }

        if (request.url.path == '/v1/councils/session-1') {
          return http.Response(
            jsonEncode({
              'session_id': 'session-1',
              'question': 'Suggest cat names for a calm gray cat.',
              'status': 'closed',
              'council_type': 'llm',
              'verdict': '**Recommended Names:**\n\n1. Misty\n2. Luna',
              'confidence_label': 'high',
              'consensus_score': 1.0,
              'dissent_detected': false,
              'created_at': '2026-06-09T10:00:00Z',
              'closed_at': '2026-06-09T10:00:02Z',
              'conflict_detected': false,
              'members': [
                {'name': 'Naming Expert'},
                {'name': 'Taste Critic'},
                {'name': 'Chair'},
              ],
              'contributions_received': 0,
            }),
            200,
          );
        }

        if (request.url.path == '/v1/socket/token') {
          return http.Response(jsonEncode({'detail': 'No realtime'}), 404);
        }

        return http.Response(jsonEncode({'detail': 'Unexpected request'}), 404);
      }),
    );
  }

  testWidgets(
    'renders question, member response, markdown verdict, and input',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 900,
              child: ChatScreen(
                sessionId: 'session-1',
                threadId: 'thread-1',
                councilStatus: 'closed',
                client: makeClient(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Question'), findsOneWidget);
      expect(
        find.text('Suggest cat names for a calm gray cat.'),
        findsOneWidget,
      );
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('llm'), findsOneWidget);
      expect(find.text('3 members'), findsOneWidget);

      expect(find.text('Naming Expert'), findsOneWidget);
      expect(find.textContaining('Misty', findRichText: true), findsWidgets);
      expect(
        find.textContaining('**Recommended', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('Recommended Names:', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Council concluded'), findsOneWidget);
      expect(
        find.text('Type a message or @ for directives...'),
        findsOneWidget,
      );
    },
  );
}
