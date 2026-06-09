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
import 'package:synapse_app/features/auth/register_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'synapse_server_url': 'http://localhost:8000',
      'synapse_auth_mode': 'local',
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
      initialLocation: '/register',
      routes: [
        GoRoute(
          path: '/register',
          builder: (_, __) => Scaffold(
            body: RegisterScreen(
              apiClient: client,
              tokenStore: TokenStore(),
              serverStore: ServerStore(),
            ),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('Login')),
        ),
        GoRoute(
          path: '/councils',
          builder: (_, __) => const Scaffold(body: Text('Councils')),
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  testWidgets('Register validates password mismatch', (tester) async {
    final client = makeClient((_) async => http.Response('{}', 200));

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'alice@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'secret-a',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'secret-b',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('Register disabled error renders readable message', (
    tester,
  ) async {
    final client = makeClient((request) async {
      expect(request.url.path, '/v1/auth/register');
      return http.Response(
        jsonEncode({'detail': 'Public registration is disabled'}),
        403,
      );
    });

    await tester.pumpWidget(wrap(client));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'alice@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'secret',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'secret',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Registration is disabled. Ask an admin to create your account.',
      ),
      findsOneWidget,
    );
  });
}
