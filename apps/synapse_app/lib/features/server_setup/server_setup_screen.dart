import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../core/config/server_store.dart';
import '../../core/auth/token_store.dart';

/// First-run and server-switch screen.
///
/// The user enters a server URL; the app calls GET /v1/info to validate
/// it and display the backend name + version before committing.  On
/// confirm, the URL and backend type are persisted and the user is sent
/// to /login.
///
/// Backend detection: Cerebro wraps /v1/info in `{"data": {...}}`.  Any
/// response with a top-level `data` object is treated as Cerebro so the
/// client can unwrap its response envelope everywhere else.
class ServerSetupScreen extends StatefulWidget {
  final ServerStore serverStore;
  final TokenStore tokenStore;

  /// Called with the confirmed URL and whether it is a Cerebro backend.
  /// Allows the app to update the live API client without a full restart.
  final void Function(String url, bool isCerebro) onServerConfigured;

  const ServerSetupScreen({
    super.key,
    required this.serverStore,
    required this.tokenStore,
    required this.onServerConfigured,
  });

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final _controller = TextEditingController();
  bool _checking = false;
  String? _error;
  _BackendPreview? _preview;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _normalise(String raw) => raw.trim().replaceAll(RegExp(r'/+$'), '');

  Future<void> _connect() async {
    final url = _normalise(_controller.text);
    if (url.isEmpty) return;

    setState(() {
      _checking = true;
      _error = null;
      _preview = null;
    });

    try {
      final uri = Uri.parse('$url/v1/info');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        setState(() {
          _error =
              'Server returned ${response.statusCode}. '
              'Is this a Synapse or Cerebro backend?';
          _checking = false;
        });
        return;
      }

      final raw = jsonDecode(response.body) as Map<String, dynamic>;

      // Cerebro wraps /v1/info in {"data": {...}}; Synapse returns bare JSON.
      final isCerebro = raw['data'] is Map<String, dynamic>;
      final body = isCerebro ? raw['data'] as Map<String, dynamic> : raw;

      final oidc = body['oidc'] as Map<String, dynamic>?;

      setState(() {
        _preview = _BackendPreview(
          url: url,
          name: (body['name'] as String?) ?? 'Synapse',
          version: (body['version'] as String?) ?? '',
          authMode: (body['auth_mode'] as String?) ?? 'jwt_hs256',
          multiTenant: (body['multi_tenant'] as bool?) ?? false,
          isCerebro: isCerebro,
          oidcIssuer: oidc?['issuer'] as String?,
          oidcClientId: oidc?['client_id'] as String?,
        );
        _checking = false;
      });
    } on FormatException {
      setState(() {
        _error =
            'Could not parse server response. '
            'Check the URL and try again.';
        _checking = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not reach server: ${e.toString().split('\n').first}';
        _checking = false;
      });
    }
  }

  Future<void> _confirm() async {
    final preview = _preview;
    if (preview == null) return;

    await widget.serverStore.setUrl(preview.url);
    await widget.serverStore.setIsCerebro(preview.isCerebro);
    await widget.serverStore.setAuthMode(preview.authMode);
    await widget.serverStore.setOidcIssuer(preview.oidcIssuer);
    await widget.serverStore.setOidcClientId(preview.oidcClientId);
    widget.onServerConfigured(preview.url, preview.isCerebro);

    if (mounted) context.go('/login');
  }

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
                  'Connect to server',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter the URL of your Synapse or Cerebro backend.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'https://api.example.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.dns),
                  ),
                  onSubmitted: (_) => _connect(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                if (_preview == null)
                  ElevatedButton(
                    onPressed: _checking ? null : _connect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _checking
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Connect'),
                  )
                else ...[
                  _BackendPreviewCard(preview: _preview!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Use this server'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _preview = null),
                    child: const Text(
                      'Change URL',
                      style: TextStyle(color: Colors.white54),
                    ),
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

class _BackendPreview {
  final String url;
  final String name;
  final String version;
  final String authMode;
  final bool multiTenant;
  final bool isCerebro;
  final String? oidcIssuer;
  final String? oidcClientId;

  const _BackendPreview({
    required this.url,
    required this.name,
    required this.version,
    required this.authMode,
    required this.multiTenant,
    required this.isCerebro,
    this.oidcIssuer,
    this.oidcClientId,
  });
}

class _BackendPreviewCard extends StatelessWidget {
  final _BackendPreview preview;

  const _BackendPreviewCard({required this.preview});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle,
                color: Color(0xFF4ADE80),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                preview.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              if (preview.version.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  preview.version,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            preview.url,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (preview.multiTenant) ...[
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(Icons.people, size: 14, color: Color(0xFF6366F1)),
                SizedBox(width: 4),
                Text(
                  'Multi-tenant',
                  style: TextStyle(color: Color(0xFF6366F1), fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
