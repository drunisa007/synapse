import 'package:flutter_test/flutter_test.dart';
import 'package:synapse_app/core/api/models.dart';

void main() {
  group('BackendInfo.fromJson', () {
    test('parses synapse response with local auth_mode', () {
      final info = BackendInfo.fromJson({
        'backend': 'synapse',
        'version': '1.2.3',
        'auth_mode': 'local',
        'multi_tenant': false,
        'billing': false,
        'features': {},
      });

      expect(info.backend, 'synapse');
      expect(info.authMode, 'local');
      expect(info.oidcIssuer, isNull);
      expect(info.oidcClientId, isNull);
      expect(info.localRegistrationOpen, isNull);
    });

    test('parses cerebro response with jwt_oidc and oidc block', () {
      final info = BackendInfo.fromJson({
        'backend': 'cerebro',
        'version': '2.0.0',
        'auth_mode': 'jwt_oidc',
        'multi_tenant': true,
        'billing': true,
        'features': {},
        'oidc': {
          'issuer': 'http://casdoor:8000',
          'client_id': 'cerebro',
          'scopes': ['openid', 'email', 'profile'],
        },
      });

      expect(info.authMode, 'jwt_oidc');
      expect(info.oidcIssuer, 'http://casdoor:8000');
      expect(info.oidcClientId, 'cerebro');
    });

    test('defaults auth_mode to jwt_hs256 when field absent', () {
      final info = BackendInfo.fromJson({
        'backend': 'synapse',
        'version': '1.0.0',
        'multi_tenant': false,
        'billing': false,
        'features': {},
      });

      expect(info.authMode, 'jwt_hs256');
    });

    test('oidc fields are null when oidc block is absent', () {
      final info = BackendInfo.fromJson({
        'backend': 'cerebro',
        'version': '1.0.0',
        'auth_mode': 'jwt_oidc',
        'multi_tenant': false,
        'billing': false,
        'features': {},
      });

      expect(info.oidcIssuer, isNull);
      expect(info.oidcClientId, isNull);
    });

    test('oidc fields are null when oidc block is null', () {
      final info = BackendInfo.fromJson({
        'backend': 'cerebro',
        'version': '1.0.0',
        'auth_mode': 'jwt_oidc',
        'multi_tenant': false,
        'billing': false,
        'features': {},
        'oidc': null,
      });

      expect(info.oidcIssuer, isNull);
      expect(info.oidcClientId, isNull);
    });

    test('parses optional local registration availability when present', () {
      final info = BackendInfo.fromJson({
        'backend': 'synapse',
        'version': '1.0.0',
        'auth_mode': 'local',
        'multi_tenant': false,
        'billing': false,
        'features': {},
        'local_registration_open': true,
      });

      expect(info.localRegistrationOpen, isTrue);
    });
  });
}
