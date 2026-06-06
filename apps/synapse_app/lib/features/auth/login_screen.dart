import 'dart:convert';

import 'package:casdoor_flutter_sdk/casdoor_flutter_sdk.dart'
    show AuthConfig, Casdoor;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../core/auth/token_store.dart';
import '../../core/config/server_store.dart';

class LoginScreen extends StatefulWidget {
  final TokenStore tokenStore;
  final ServerStore serverStore;

  const LoginScreen({
    super.key,
    required this.tokenStore,
    required this.serverStore,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Shared state
  String? _serverUrl;
  String _authMode = 'jwt_hs256';
  String? _oidcIssuer;
  String? _oidcClientId;
  bool _loading = false;
  String? _error;

  // Token-paste mode
  final _tokenController = TextEditingController();
  String? _currentPrefix;

  // Local auth mode
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = await widget.tokenStore.getToken();
    final url = await widget.serverStore.getUrl();
    final authMode = await widget.serverStore.getAuthMode();
    final oidcIssuer = await widget.serverStore.getOidcIssuer();
    final oidcClientId = await widget.serverStore.getOidcClientId();

    if (mounted) {
      setState(() {
        _serverUrl = url;
        _authMode = authMode;
        _oidcIssuer = oidcIssuer;
        _oidcClientId = oidcClientId;
        _currentPrefix = (token != null && token.length > 12)
            ? '${token.substring(0, 12)}…'
            : token;
      });
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── OIDC / Casdoor PKCE flow ────────────────────────────────────────────

  Future<void> _loginWithCasdoor() async {
    final issuer = _oidcIssuer;
    final clientId = _oidcClientId;
    if (issuer == null || clientId == null) {
      setState(
        () => _error = 'OIDC configuration missing. Re-connect to the server.',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final config = AuthConfig(
        serverUrl: issuer,
        clientId: clientId,
        appName: clientId,
        organizationName: 'built-in',
        redirectUri: 'synapse://auth/callback',
        callbackUrlScheme: 'synapse',
      );

      final sdk = Casdoor(config: config);
      final callbackUrl = await sdk.show(
        scope: 'openid email profile offline_access',
      );
      final code = Uri.parse(callbackUrl).queryParameters['code'] ?? '';
      final response = await sdk.requestOauthAccessToken(code);
      final tokenData = jsonDecode(response.body) as Map<String, dynamic>;
      final accessToken = tokenData['access_token'] as String?;

      if (accessToken == null || accessToken.isEmpty) {
        setState(() => _error = 'Sign-in failed: no access token returned.');
        return;
      }

      await widget.tokenStore.setToken(accessToken);
      if (mounted) context.go('/councils');
    } catch (e) {
      setState(
        () => _error = 'Sign-in failed: ${e.toString().split('\n').first}',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Local email / password flow ─────────────────────────────────────────

  Future<void> _loginLocal() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse('${_serverUrl!}/v1/auth/login');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final token = body['access_token'] as String?;
        if (token != null) {
          await widget.tokenStore.setToken(token);
          if (mounted) context.go('/councils');
        }
      } else if (response.statusCode == 401) {
        setState(() => _error = 'Invalid email or password.');
      } else {
        setState(() => _error = 'Login failed (${response.statusCode}).');
      }
    } catch (e) {
      setState(
        () => _error =
            'Could not reach server: ${e.toString().split('\n').first}',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Token-paste flow (dev / API key) ────────────────────────────────────

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) return;
    setState(() => _loading = true);
    await widget.tokenStore.setToken(token);
    if (mounted) context.go('/councils');
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.hub, size: 48, color: Color(0xFF6366F1)),
                const SizedBox(height: 16),
                const Text(
                  'Synapse',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Multi-agent deliberation system',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
                if (_serverUrl != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.dns, size: 13, color: Colors.white38),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _serverUrl!,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => context.go('/server-setup'),
                        child: const Text(
                          'Change',
                          style: TextStyle(
                            color: Color(0xFF6366F1),
                            fontSize: 12,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 32),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_authMode == 'jwt_oidc') ...[
                  _OidcLoginPanel(loading: _loading, onTap: _loginWithCasdoor),
                ] else if (_authMode == 'local') ...[
                  _LocalLoginPanel(
                    emailController: _emailController,
                    passwordController: _passwordController,
                    loading: _loading,
                    onSubmit: _loginLocal,
                  ),
                ] else ...[
                  _TokenPastePanel(
                    controller: _tokenController,
                    currentPrefix: _currentPrefix,
                    loading: _loading,
                    onSubmit: _saveToken,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── OIDC panel ──────────────────────────────────────────────────────────────

class _OidcLoginPanel extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;

  const _OidcLoginPanel({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: loading ? null : onTap,
      icon: loading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.login),
      label: const Text('Sign in with Casdoor'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF6366F1),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}

// ── Local email/password panel ───────────────────────────────────────────────

class _LocalLoginPanel extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool loading;
  final VoidCallback onSubmit;

  const _LocalLoginPanel({
    required this.emailController,
    required this.passwordController,
    required this.loading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: emailController,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email_outlined),
          ),
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock_outline),
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: loading ? null : onSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Sign in'),
        ),
      ],
    );
  }
}

// ── Token-paste panel (dev / API key) ────────────────────────────────────────

class _TokenPastePanel extends StatelessWidget {
  final TextEditingController controller;
  final String? currentPrefix;
  final bool loading;
  final VoidCallback onSubmit;

  const _TokenPastePanel({
    required this.controller,
    required this.currentPrefix,
    required this.loading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (currentPrefix != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Current token: $currentPrefix',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
        TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Bearer Token / API Key',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.vpn_key),
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: loading ? null : onSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save & Continue'),
        ),
      ],
    );
  }
}
