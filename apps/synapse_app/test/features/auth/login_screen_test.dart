import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synapse_app/core/api/client.dart';
import 'package:synapse_app/core/auth/token_store.dart';
import 'package:synapse_app/core/config/server_store.dart';
import 'package:synapse_app/features/auth/login_screen.dart';

/// Wraps [LoginScreen] in a minimal GoRouter so context.go() doesn't throw.
Widget _buildScreen({required Map<String, Object> prefs}) {
  SharedPreferences.setMockInitialValues(prefs);
  final tokenStore = TokenStore();
  final client = SynapseApiClient(
    baseUrl:
        (prefs['synapse_server_url'] as String?) ?? 'http://localhost:8000',
    tokenStore: tokenStore,
    httpClient: MockClient((_) async => http.Response('{}', 200)),
  );

  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => LoginScreen(
          tokenStore: tokenStore,
          serverStore: ServerStore(),
          apiClient: client,
        ),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const Scaffold(body: Text('Register')),
      ),
      GoRoute(
        path: '/councils',
        builder: (_, __) => const Scaffold(body: Text('Councils')),
      ),
      GoRoute(
        path: '/server-setup',
        builder: (_, __) => const Scaffold(body: Text('Setup')),
      ),
    ],
  );

  return MaterialApp.router(routerConfig: router);
}

void main() {
  group('LoginScreen — token-paste mode (jwt_hs256 / default)', () {
    testWidgets('shows Bearer Token text field', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          prefs: {
            'synapse_server_url': 'http://localhost:8000',
            'synapse_auth_mode': 'jwt_hs256',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bearer Token / API Key'), findsOneWidget);
      expect(find.text('Save & Continue'), findsOneWidget);
    });

    testWidgets('does not show OIDC or email/password widgets', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          prefs: {
            'synapse_server_url': 'http://localhost:8000',
            'synapse_auth_mode': 'jwt_hs256',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign in with Casdoor'), findsNothing);
      expect(find.text('Email'), findsNothing);
      expect(find.text('Password'), findsNothing);
    });
  });

  group('LoginScreen — local auth mode', () {
    testWidgets('shows email and password fields', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          prefs: {
            'synapse_server_url': 'http://localhost:8000',
            'synapse_auth_mode': 'local',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
    });

    testWidgets('does not show OIDC or token-paste widgets', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          prefs: {
            'synapse_server_url': 'http://localhost:8000',
            'synapse_auth_mode': 'local',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign in with Casdoor'), findsNothing);
      expect(find.text('Bearer Token / API Key'), findsNothing);
    });
  });

  group('LoginScreen — jwt_oidc mode', () {
    testWidgets('shows Sign in with Casdoor button', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          prefs: {
            'synapse_server_url': 'http://localhost:8000',
            'synapse_auth_mode': 'jwt_oidc',
            'synapse_oidc_issuer': 'http://casdoor:8000',
            'synapse_oidc_client_id': 'cerebro',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign in with Casdoor'), findsOneWidget);
    });

    testWidgets('does not show email/password or token-paste widgets', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildScreen(
          prefs: {
            'synapse_server_url': 'http://localhost:8000',
            'synapse_auth_mode': 'jwt_oidc',
            'synapse_oidc_issuer': 'http://casdoor:8000',
            'synapse_oidc_client_id': 'cerebro',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Email'), findsNothing);
      expect(find.text('Password'), findsNothing);
      expect(find.text('Bearer Token / API Key'), findsNothing);
    });
  });

  group('LoginScreen — server URL display', () {
    testWidgets('shows server URL when set', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          prefs: {
            'synapse_server_url': 'http://localhost:8000',
            'synapse_auth_mode': 'jwt_hs256',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('http://localhost:8000'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
    });

    testWidgets('shows current token prefix when token exists', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          prefs: {
            'synapse_server_url': 'http://localhost:8000',
            'synapse_auth_mode': 'jwt_hs256',
            'synapse_bearer_token': 'my-long-token-value',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Current token:'), findsOneWidget);
    });
  });
}
