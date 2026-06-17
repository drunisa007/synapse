import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/client.dart';
import '../../core/auth/token_store.dart';
import '../../core/config/server_store.dart';
import '../../core/routing/app_paths.dart';

class RegisterScreen extends StatefulWidget {
  final SynapseApiClient apiClient;
  final TokenStore tokenStore;
  final ServerStore serverStore;

  const RegisterScreen({
    super.key,
    required this.apiClient,
    required this.tokenStore,
    required this.serverStore,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _serverUrl;
  String _authMode = 'jwt_hs256';
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final serverUrl = await widget.serverStore.getUrl();
    final authMode = await widget.serverStore.getAuthMode();
    if (!mounted) return;
    setState(() {
      _serverUrl = serverUrl;
      _authMode = authMode;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (email.isEmpty) {
      setState(() => _error = 'Email is required.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Password is required.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final token = await widget.apiClient.registerLocalUser(
        email: email,
        password: password,
      );
      await widget.tokenStore.setToken(token.accessToken);
      if (mounted) context.go(AppPaths.councilList);
    } on ApiException catch (e) {
      final message = switch (e.statusCode) {
        403 => 'Registration is disabled. Ask an admin to create your account.',
        409 => 'Email already registered.',
        501 => 'Local auth is not enabled on this server.',
        _ => e.message,
      };
      if (mounted) setState(() => _error = message);
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not register: ${e.toString().split('\n').first}',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.go(AppPaths.login),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _authMode == 'local'
                ? _form()
                : _notAvailable(),
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.person_add_alt_1, size: 44, color: Color(0xFF6366F1)),
        const SizedBox(height: 16),
        const Text(
          'Create account',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        if (_serverUrl != null) ...[
          const SizedBox(height: 8),
          Text(
            _serverUrl!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 28),
        TextField(
          controller: _emailController,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Confirm password',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock_reset_outlined),
          ),
          onSubmitted: (_) => _register(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _submitting ? null : _register,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create account'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _submitting ? null : () => context.go(AppPaths.login),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }

  Widget _notAvailable() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.block_outlined, size: 42, color: Colors.white38),
        const SizedBox(height: 16),
        const Text(
          'Registration unavailable',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'This server is not using local email/password authentication.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => context.go(AppPaths.login),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back to sign in'),
        ),
      ],
    );
  }
}
