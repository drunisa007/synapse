import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synapse_app/core/api/client.dart';
import 'package:synapse_app/core/api/models.dart';
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

  group('SynapseApiClient auth/profile', () {
    test('getCurrentUser parses /auth/me', () async {
      final client = makeClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/auth/me');
        expect(request.headers['Authorization'], 'Bearer test-token');
        return http.Response(
          jsonEncode({
            'id': 'user-1',
            'email': 'alice@example.com',
            'role': 'admin',
          }),
          200,
        );
      });

      final user = await client.getCurrentUser();

      expect(user.id, 'user-1');
      expect(user.email, 'alice@example.com');
      expect(user.role, 'admin');
    });

    test('registerLocalUser sends email/password and parses token', () async {
      Map<String, dynamic>? body;
      final client = makeClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/auth/register');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'access_token': 'registered-token',
            'token_type': 'bearer',
            'expires_in': 3600,
          }),
          201,
        );
      });

      final token = await client.registerLocalUser(
        email: 'alice@example.com',
        password: 'secret',
      );

      expect(body, {'email': 'alice@example.com', 'password': 'secret'});
      expect(token.accessToken, 'registered-token');
      expect(token.tokenType, 'bearer');
      expect(token.expiresIn, 3600);
    });

    test('loginLocalUser sends email/password and parses token', () async {
      Map<String, dynamic>? body;
      final client = makeClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/auth/login');
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'access_token': 'login-token'}), 200);
      });

      final token = await client.loginLocalUser(
        email: 'alice@example.com',
        password: 'secret',
      );

      expect(body, {'email': 'alice@example.com', 'password': 'secret'});
      expect(token.accessToken, 'login-token');
      expect(token.tokenType, 'bearer');
    });

    test('/auth/me 501 surfaces as ApiException', () async {
      final client = makeClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Local auth is not enabled (SYNAPSE_AUTH_MODE != local)',
          }),
          501,
        );
      });

      await expectLater(
        client.getCurrentUser(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 501)
              .having((e) => e.message, 'message', contains('Local auth')),
        ),
      );
    });

    test('/auth/me 403 surfaces as ApiException', () async {
      final client = makeClient((request) async {
        return http.Response(jsonEncode({'detail': 'Forbidden'}), 403);
      });

      await expectLater(
        client.getCurrentUser(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });
  });

  group('TokenIdentity', () {
    test('parses JWT claims defensively', () {
      final payload = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'sub': 'user-1',
                'email': 'alice@example.com',
                'roles': ['member', 'admin'],
                'tenant_id': 'tenant-a',
              }),
            ),
          )
          .replaceAll('=', '');
      final identity = TokenIdentity.tryParseJwt('header.$payload.signature');

      expect(identity?.sub, 'user-1');
      expect(identity?.email, 'alice@example.com');
      expect(identity?.roles, ['member', 'admin']);
      expect(identity?.tenantId, 'tenant-a');
    });

    test('returns null for non-JWT tokens', () {
      expect(TokenIdentity.tryParseJwt('plain-api-key'), isNull);
    });
  });
}
