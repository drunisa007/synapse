import 'dart:convert';
import 'package:http/http.dart' as http;
import '../auth/token_store.dart';
import 'models.dart';
import '../realtime/realtime_client.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class SynapseApiClient {
  // Non-final: updated when the user switches server without a full app restart.
  String baseUrl;

  // Cerebro wraps every REST response in {"data": ...}.  Set true when the
  // live server is a Cerebro backend so _unwrap/_unwrapList strip the envelope.
  bool isCerebro;

  final TokenStore tokenStore;
  final http.Client _httpClient;

  SynapseApiClient({
    required this.baseUrl,
    required this.tokenStore,
    this.isCerebro = false,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  Future<Map<String, String>> _authHeaders() async {
    final token = await tokenStore.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  void _checkResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message;
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        message =
            (body['detail'] as String?) ??
            (body['message'] as String?) ??
            response.body;
      } catch (_) {
        message = response.body;
      }
      throw ApiException(response.statusCode, message);
    }
  }

  /// Strips Cerebro's `{"data": {...}}` envelope for single-object responses.
  Map<String, dynamic> _unwrap(Map<String, dynamic> body) {
    if (isCerebro) {
      final data = body['data'];
      if (data is Map<String, dynamic>) return data;
    }
    return body;
  }

  /// Strips Cerebro's `{"data": [...]}` envelope for list responses.
  List<dynamic> _unwrapList(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is List) return data;
      final events = decoded['events'];
      if (events is List) return events;
    }
    if (decoded is List) return decoded;
    return const [];
  }

  Future<List<CouncilSummary>> listCouncils({
    int limit = 50,
    int offset = 0,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/councils?limit=$limit&offset=$offset');
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    final list = _unwrapList(jsonDecode(response.body));
    return list
        .map((e) => CouncilSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CouncilDetail> getCouncil(String sessionId) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/councils/$sessionId');
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    return CouncilDetail.fromJson(
      _unwrap(jsonDecode(response.body) as Map<String, dynamic>),
    );
  }

  Future<String> getCouncilThreadId(String sessionId) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/councils/$sessionId/thread');
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    final body = _unwrap(jsonDecode(response.body) as Map<String, dynamic>);
    return body['thread_id'] as String;
  }

  Future<CreateCouncilResponse> createCouncil({
    required String question,
    String? templateId,
    String? councilType,
    CouncilMode mode = CouncilMode.standard,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{'question': question};
    if (templateId != null) body['template_id'] = templateId;
    if (councilType != null) body['council_type'] = councilType;
    // Canonical opt-in for red team / deliberation is `settings.mode`. Both
    // backends accept it: Cerebro reads it directly; Synapse accepts
    // `settings` as an alias for its internal `config` field and promotes
    // `settings.mode == "red_team"` into the legacy `council_type` field
    // server-side. Standard mode omits the settings block entirely.
    if (mode != CouncilMode.standard) {
      body['settings'] = {'mode': mode.wire};
    }

    final uri = Uri.parse('$baseUrl/v1/councils');
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    _checkResponse(response);
    return CreateCouncilResponse.fromJson(
      _unwrap(jsonDecode(response.body) as Map<String, dynamic>),
    );
  }

  Future<void> closeCouncil(String sessionId) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/councils/$sessionId/close');
    final response = await _httpClient.post(uri, headers: headers);
    _checkResponse(response);
  }

  Future<void> approveCouncil(String sessionId) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/councils/$sessionId/approve');
    final response = await _httpClient.post(uri, headers: headers);
    _checkResponse(response);
  }

  /// GET /v1/workspace/users — recently-active principals for the chat
  /// @mention picker. Optional `q` filters server-side on display name /
  /// id (case-insensitive substring). Returns `[]` on 404 (Synapse OSS
  /// doesn't have parity yet) so callers can degrade to email-only mode
  /// without an extra error-handling layer.
  Future<List<WorkspaceUser>> listWorkspaceUsers({
    String? q,
    int limit = 25,
  }) async {
    final headers = await _authHeaders();
    final params = <String, String>{'limit': '$limit'};
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    final uri = Uri.parse(
      '$baseUrl/v1/workspace/users',
    ).replace(queryParameters: params);
    final response = await _httpClient.get(uri, headers: headers);
    if (response.statusCode == 404) return const [];
    _checkResponse(response);
    final list = _unwrapList(jsonDecode(response.body));
    return list
        .map((e) => WorkspaceUser.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ContributeResponse> contribute(
    String sessionId, {
    required String memberId,
    required String memberName,
    required String content,
  }) async {
    final headers = await _authHeaders();
    final body = {
      'member_id': memberId,
      'member_name': memberName,
      'content': content,
    };
    final uri = Uri.parse('$baseUrl/v1/councils/$sessionId/contribute');
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    _checkResponse(response);
    return ContributeResponse.fromJson(
      _unwrap(jsonDecode(response.body) as Map<String, dynamic>),
    );
  }

  Future<List<ThreadEvent>> listEvents(
    String threadId, {
    int? afterId,
    int limit = 50,
  }) async {
    final headers = await _authHeaders();
    final params = <String, String>{'limit': '$limit'};
    if (afterId != null) params['after_id'] = '$afterId';
    final uri = Uri.parse(
      '$baseUrl/v1/threads/$threadId/events',
    ).replace(queryParameters: params);
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    final list = _unwrapList(jsonDecode(response.body));
    return list
        .map((e) => ThreadEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ChatResponse> chatWithVerdict(String sessionId, String message) async {
    final headers = await _authHeaders();
    final body = {'message': message};
    final uri = Uri.parse('$baseUrl/v1/councils/$sessionId/chat');
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    _checkResponse(response);
    return ChatResponse.fromJson(
      _unwrap(jsonDecode(response.body) as Map<String, dynamic>),
    );
  }

  Future<List<Template>> listTemplates() async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/templates');
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    final list = _unwrapList(jsonDecode(response.body));
    return list
        .map((e) => Template.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> getCentrifugoToken() async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/centrifugo/token');
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    final body = _unwrap(jsonDecode(response.body) as Map<String, dynamic>);
    return body['token'] as String;
  }

  Future<RealtimeDescriptor> getRealtimeDescriptor() async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/socket/token');
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    return RealtimeDescriptor.fromJson(
      _unwrap(jsonDecode(response.body) as Map<String, dynamic>),
    );
  }

  // ─── Backend metadata (X-2) — public, no auth ─────────────────────────────

  Future<BackendInfo> getBackendInfo() async {
    final uri = Uri.parse('$baseUrl/v1/info');
    final response = await _httpClient.get(uri);
    _checkResponse(response);
    final raw = jsonDecode(response.body) as Map<String, dynamic>;
    // Cerebro wraps /v1/info too — strip the envelope before parsing.
    final body = raw['data'] is Map<String, dynamic>
        ? raw['data'] as Map<String, dynamic>
        : raw;
    return BackendInfo.fromJson(body);
  }

  // ─── Notifications (B10 / W9 / F3) ────────────────────────────────────────

  Future<NotificationPreferences> getNotificationPreferences() async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/notifications/preferences');
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    return NotificationPreferences.fromJson(
      _unwrap(jsonDecode(response.body) as Map<String, dynamic>),
    );
  }

  Future<NotificationPreferences> updateNotificationPreferences({
    required bool emailEnabled,
    String? emailAddress,
    required bool ntfyEnabled,
    // Optional so callers that don't care about FCM/APNs gating (or are
    // hitting a Synapse OSS backend that doesn't have the field yet) can
    // omit it. The backend tolerates partial PUTs — anything absent
    // keeps its current value.
    bool? pushEnabled,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{
      'email_enabled': emailEnabled,
      'email_address': emailAddress,
      'ntfy_enabled': ntfyEnabled,
      if (pushEnabled != null) 'push_enabled': pushEnabled,
    };
    final uri = Uri.parse('$baseUrl/v1/notifications/preferences');
    final response = await _httpClient.put(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    _checkResponse(response);
    return NotificationPreferences.fromJson(
      _unwrap(jsonDecode(response.body) as Map<String, dynamic>),
    );
  }

  Future<List<DeviceToken>> listDeviceTokens() async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/notifications/devices');
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    final body = _unwrap(jsonDecode(response.body) as Map<String, dynamic>);
    final list = (body['devices'] as List<dynamic>?) ?? [];
    return list
        .map((e) => DeviceToken.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DeviceToken> registerDeviceToken({
    required String token,
    String tokenType = 'ntfy',
    String? deviceLabel,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{'token': token, 'token_type': tokenType};
    if (deviceLabel != null) body['device_label'] = deviceLabel;
    final uri = Uri.parse('$baseUrl/v1/notifications/devices');
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    _checkResponse(response);
    return DeviceToken.fromJson(
      _unwrap(jsonDecode(response.body) as Map<String, dynamic>),
    );
  }

  Future<void> deleteDeviceToken(String tokenId) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/notifications/devices/$tokenId');
    final response = await _httpClient.delete(uri, headers: headers);
    _checkResponse(response);
  }

  Future<List<FeedItem>> getNotificationFeed({int limit = 20}) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/notifications/feed?limit=$limit');
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    final body = _unwrap(jsonDecode(response.body) as Map<String, dynamic>);
    final list = (body['items'] as List<dynamic>?) ?? [];
    return list
        .map((e) => FeedItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Memory (F-extend, B12) ───────────────────────────────────────────────

  Future<List<MemoryHit>> searchMemory(
    String query, {
    String bank = 'decisions',
    int limit = 10,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse(
      '$baseUrl/v1/memory/search?q=${Uri.encodeQueryComponent(query)}'
      '&bank=$bank&limit=$limit',
    );
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    final body = _unwrap(jsonDecode(response.body) as Map<String, dynamic>);
    final list = (body['hits'] as List<dynamic>?) ?? [];
    return list
        .map((e) => MemoryHit.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── Analytics (B8 / F-extend) ────────────────────────────────────────────

  Future<Map<String, dynamic>> getAnalyticsConsensus() async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/analytics/consensus');
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    return _unwrap(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getAnalyticsVelocity({int days = 30}) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/analytics/velocity?days=$days');
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    return _unwrap(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<dynamic>> getAnalyticsMembers({int limit = 20}) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/analytics/members?limit=$limit');
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    final body = _unwrap(jsonDecode(response.body) as Map<String, dynamic>);
    return (body['data'] as List<dynamic>?) ?? [];
  }

  // -------------------------------------------------------------------------
  // Chat-with-tools (Mode 4) — free-standing chat sessions.
  // -------------------------------------------------------------------------

  Future<ChatSession> createChatSession({
    String? title,
    AgentConfig? agentConfig,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/chat/sessions');
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode({
        if (title != null) 'title': title,
        if (agentConfig != null) 'agent_config': agentConfig.toJson(),
      }),
    );
    _checkResponse(response);
    return ChatSession.fromJson(
      _unwrap(jsonDecode(response.body) as Map<String, dynamic>),
    );
  }

  Future<ListChatSessionsResponse> listChatSessions({
    String status = 'active',
    int limit = 50,
    String? before,
  }) async {
    final headers = await _authHeaders();
    final qs = <String, String>{'status': status, 'limit': '$limit'};
    if (before != null) qs['before'] = before;
    final uri = Uri.parse(
      '$baseUrl/v1/chat/sessions',
    ).replace(queryParameters: qs);
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    // The list response is itself an envelope ({data, next_before_id}).
    // Don't run it through _unwrap — under Cerebro that would strip the
    // outer envelope and the inner one would look like the response.
    return ListChatSessionsResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ChatSession> getChatSession(String id) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/chat/sessions/$id');
    final response = await _httpClient.get(uri, headers: headers);
    _checkResponse(response);
    return ChatSession.fromJson(
      _unwrap(jsonDecode(response.body) as Map<String, dynamic>),
    );
  }

  Future<ChatSession> updateChatSession(
    String id, {
    String? title,
    String? status,
    AgentConfig? agentConfig,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/chat/sessions/$id');
    final response = await _httpClient.patch(
      uri,
      headers: headers,
      body: jsonEncode({
        if (title != null) 'title': title,
        if (status != null) 'status': status,
        if (agentConfig != null) 'agent_config': agentConfig.toJson(),
      }),
    );
    _checkResponse(response);
    return ChatSession.fromJson(
      _unwrap(jsonDecode(response.body) as Map<String, dynamic>),
    );
  }

  /// Soft-delete: flips status to "archived", returns 204.
  Future<void> archiveChatSession(String id) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/chat/sessions/$id');
    final response = await _httpClient.delete(uri, headers: headers);
    _checkResponse(response);
  }

  /// POST /v1/chat/sessions/:id/messages — yields one [ChatSseEvent] per
  /// server frame. The consumer dispatches on the runtime subtype (sealed
  /// over the six event types defined in chat.md §4a).
  ///
  /// The stream ends when the server closes the connection. Callers should
  /// treat the absence of a final [MessageCompleteEvent] as a failed turn —
  /// status is locked to 200 by send_chunked/2 so the only honest failure
  /// signal is an in-body [ChatErrorEvent] or a missing message_complete.
  /// `humans` carries any @-mentioned contributors from the chat-input
  /// picker. The backend merges them with whatever the LLM emits in the
  /// `synapse_council_start` tool call args — picker is ground truth,
  /// the LLM's text framing is just how the user asked.
  Stream<ChatSseEvent> streamChatMessage(
    String sessionId,
    String content, {
    List<PendingHuman> humans = const [],
  }) => _streamSse('/v1/chat/sessions/$sessionId/messages', {
    'content': content,
    if (humans.isNotEmpty)
      'humans': humans.map((h) => h.toJson()).toList(growable: false),
  });

  // -------------------------------------------------------------------------
  // Conversation editing (Phase 1B) — fork / edit / regenerate.
  // -------------------------------------------------------------------------

  /// POST /v1/chat/sessions/:id/fork — creates a child session whose
  /// thread is a copy of the parent's up to and including [fromEventId].
  /// The parent thread gets a `conversation_forked` marker event.
  Future<ChatSession> forkChatSession(
    String sessionId,
    int fromEventId, {
    String? title,
  }) async {
    final headers = await _authHeaders();
    final uri = Uri.parse('$baseUrl/v1/chat/sessions/$sessionId/fork');
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'from_event_id': fromEventId,
        if (title != null) 'title': title,
      }),
    );
    _checkResponse(response);
    return ChatSession.fromJson(
      _unwrap(jsonDecode(response.body) as Map<String, dynamic>),
    );
  }

  /// POST /v1/chat/sessions/:id/messages/:messageId/edit — edits a user
  /// message in place and streams the regenerated agent turn. Only user
  /// messages can be edited (server returns 422 otherwise).
  Stream<ChatSseEvent> editChatMessage(
    String sessionId,
    int messageId,
    String content,
  ) => _streamSse('/v1/chat/sessions/$sessionId/messages/$messageId/edit', {
    'content': content,
  });

  /// POST /v1/chat/sessions/:id/messages/:messageId/regenerate — re-runs
  /// the agent for the user message that produced the target reflection.
  ///
  /// [agentConfigOverride] is in-memory only — the session row is NOT
  /// mutated. Use it to try a different model on this regeneration only.
  Stream<ChatSseEvent> regenerateChatMessage(
    String sessionId,
    int messageId, {
    AgentConfig? agentConfigOverride,
  }) => _streamSse(
    '/v1/chat/sessions/$sessionId/messages/$messageId/regenerate',
    agentConfigOverride == null
        ? const <String, dynamic>{}
        : {'agent_config_override': agentConfigOverride.toJson()},
  );

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /// Shared SSE decoder for the three streaming chat endpoints.
  Stream<ChatSseEvent> _streamSse(
    String path,
    Map<String, dynamic> body,
  ) async* {
    final headers = await _authHeaders();
    final req = http.Request('POST', Uri.parse('$baseUrl$path'))
      ..headers.addAll(headers)
      ..body = jsonEncode(body);

    final res = await _httpClient.send(req);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final responseBody = await res.stream.bytesToString();
      throw ApiException(res.statusCode, responseBody);
    }

    var buffer = '';
    // utf8.decoder is a StreamTransformer that handles multi-byte boundary
    // splits across chunk reads safely.
    await for (final chunk in res.stream.transform(utf8.decoder)) {
      buffer += chunk;
      while (true) {
        final sep = buffer.indexOf('\n\n');
        if (sep == -1) break;
        final frame = buffer.substring(0, sep);
        buffer = buffer.substring(sep + 2);
        final payload = frame
            .split('\n')
            .where((l) => l.startsWith('data: '))
            .map((l) => l.substring(6))
            .join();
        if (payload.isEmpty) continue;
        try {
          final json = jsonDecode(payload);
          if (json is! Map<String, dynamic>) continue;
          final evt = ChatSseEvent.fromJson(json);
          if (evt != null) yield evt;
        } catch (_) {
          // Drop malformed frames silently — see chat.md §4a, the contract
          // is that each `data:` line is a single JSON object.
        }
      }
    }
  }
}
