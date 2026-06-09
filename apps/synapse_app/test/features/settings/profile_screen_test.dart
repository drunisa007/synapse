import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synapse_app/core/api/client.dart';
import 'package:synapse_app/core/auth/token_store.dart';
import 'package:synapse_app/core/config/server_store.dart';
import 'package:synapse_app/features/settings/profile_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'synapse_server_url': 'http://localhost:8000',
      'synapse_auth_mode': 'local',
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

  Widget wrap(SynapseApiClient client) {
    final router = GoRouter(
      initialLocation: '/settings/profile',
      routes: [
        GoRoute(
          path: '/settings/profile',
          builder: (_, __) => Scaffold(
            body: ProfileScreen(
              apiClient: client,
              tokenStore: TokenStore(),
              serverStore: ServerStore(),
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const Scaffold(body: Text('Settings')),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('Login')),
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('Profile renders current user', (tester) async {
    final client = makeClient((request) async {
      expect(request.url.path, '/v1/auth/me');
      return http.Response(
        jsonEncode({
          'id': 'user-1',
          'email': 'alice@example.com',
          'role': 'admin',
        }),
        200,
      );
    });

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('alice@example.com'), findsWidgets);
    expect(find.text('admin'), findsOneWidget);
    expect(find.text('Local email/password'), findsOneWidget);
    expect(find.text('http://localhost:8000'), findsOneWidget);
  });

  testWidgets('Logout clears token and navigates to login', (tester) async {
    final client = makeClient((request) async {
      return http.Response(
        jsonEncode({
          'id': 'user-1',
          'email': 'alice@example.com',
          'role': 'member',
        }),
        200,
      );
    });

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Log out'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(await TokenStore().getToken(), isNull);
    expect(await ServerStore().getUrl(), 'http://localhost:8000');
  });
}
