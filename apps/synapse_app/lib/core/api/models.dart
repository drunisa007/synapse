class CouncilSummary {
  final String sessionId;
  final String question;
  final String status;
  final String councilType;
  final double? consensusScore;
  final String? confidenceLabel;
  final String createdAt;
  final String? closedAt;
  final String? failureReason;
  final bool conflictDetected;

  const CouncilSummary({
    required this.sessionId,
    required this.question,
    required this.status,
    required this.councilType,
    this.consensusScore,
    this.confidenceLabel,
    required this.createdAt,
    this.closedAt,
    this.failureReason,
    required this.conflictDetected,
  });

  factory CouncilSummary.fromJson(Map<String, dynamic> json) {
    return CouncilSummary(
      sessionId: json['session_id'] as String,
      question: json['question'] as String,
      status: json['status'] as String,
      councilType: json['council_type'] as String,
      consensusScore: (json['consensus_score'] as num?)?.toDouble(),
      confidenceLabel: json['confidence_label'] as String?,
      createdAt: json['created_at'] as String,
      closedAt: json['closed_at'] as String?,
      failureReason: json['failure_reason'] as String?,
      conflictDetected: (json['conflict_detected'] as bool?) ?? false,
    );
  }
}

class CouncilDetail extends CouncilSummary {
  final String? verdict;
  final bool dissentDetected;
  final String? topicTag;
  final String? templateId;
  final int? quorum;
  final int contributionsReceived;
  final String? contributionDeadline;
  final String? runAt;
  final List<Map<String, dynamic>> members;
  final Map<String, dynamic>? conflictMetadata;

  /// Red team + multi-round critique rounds. Empty when the council ran
  /// in standard mode. See docs/_design/realtime.md §5.
  final List<DeliberationRound> deliberationRounds;

  const CouncilDetail({
    required super.sessionId,
    required super.question,
    required super.status,
    required super.councilType,
    super.consensusScore,
    super.confidenceLabel,
    required super.createdAt,
    super.closedAt,
    super.failureReason,
    required super.conflictDetected,
    this.verdict,
    required this.dissentDetected,
    this.topicTag,
    this.templateId,
    this.quorum,
    required this.contributionsReceived,
    this.contributionDeadline,
    this.runAt,
    required this.members,
    this.conflictMetadata,
    this.deliberationRounds = const [],
  });

  factory CouncilDetail.fromJson(Map<String, dynamic> json) {
    final members =
        (json['members'] as List<dynamic>?)
            ?.map((m) => Map<String, dynamic>.from(m as Map))
            .toList() ??
        [];
    final conflictMeta = json['conflict_metadata'] != null
        ? Map<String, dynamic>.from(json['conflict_metadata'] as Map)
        : null;
    final rounds =
        (json['deliberation_rounds'] as List<dynamic>?)
            ?.map(
              (r) => DeliberationRound.fromJson(
                Map<String, dynamic>.from(r as Map),
              ),
            )
            .toList() ??
        const <DeliberationRound>[];

    return CouncilDetail(
      sessionId: json['session_id'] as String,
      question: json['question'] as String,
      status: json['status'] as String,
      councilType: json['council_type'] as String,
      consensusScore: (json['consensus_score'] as num?)?.toDouble(),
      confidenceLabel: json['confidence_label'] as String?,
      createdAt: json['created_at'] as String,
      closedAt: json['closed_at'] as String?,
      failureReason: json['failure_reason'] as String?,
      conflictDetected: (json['conflict_detected'] as bool?) ?? false,
      verdict: json['verdict'] as String?,
      dissentDetected: (json['dissent_detected'] as bool?) ?? false,
      topicTag: json['topic_tag'] as String?,
      templateId: json['template_id'] as String?,
      quorum: json['quorum'] as int?,
      contributionsReceived: (json['contributions_received'] as int?) ?? 0,
      contributionDeadline: json['contribution_deadline'] as String?,
      runAt: json['run_at'] as String?,
      members: members,
      conflictMetadata: conflictMeta,
      deliberationRounds: rounds,
    );
  }
}

/// One entry in `council.deliberation_rounds`. The shape varies by [mode]:
///
///   - `mode == "red_team"`: [attacks] is populated, [critiques] +
///     [revisedResponses] are empty.
///   - `mode == "deliberation"`: [critiques] + [revisedResponses] are
///     populated, [attacks] is empty.
class DeliberationRound {
  final int round;
  final String mode; // "red_team" | "deliberation"
  final bool converged;
  final List<MemberCritique> attacks;
  final List<MemberCritique> critiques;
  final List<Map<String, dynamic>> revisedResponses;

  const DeliberationRound({
    required this.round,
    required this.mode,
    required this.converged,
    this.attacks = const [],
    this.critiques = const [],
    this.revisedResponses = const [],
  });

  factory DeliberationRound.fromJson(Map<String, dynamic> json) {
    List<MemberCritique> critiques(String key) =>
        (json[key] as List<dynamic>?)
            ?.map(
              (c) =>
                  MemberCritique.fromJson(Map<String, dynamic>.from(c as Map)),
            )
            .toList() ??
        const <MemberCritique>[];

    return DeliberationRound(
      round: (json['round'] as int?) ?? 0,
      mode: (json['mode'] as String?) ?? '',
      converged: (json['converged'] as bool?) ?? false,
      attacks: critiques('attacks'),
      critiques: critiques('critiques'),
      revisedResponses:
          (json['revised_responses'] as List<dynamic>?)
              ?.map((r) => Map<String, dynamic>.from(r as Map))
              .toList() ??
          const <Map<String, dynamic>>[],
    );
  }
}

class MemberCritique {
  final String? memberId;
  final String memberName;
  final String critique;
  final String? error;

  const MemberCritique({
    required this.memberId,
    required this.memberName,
    required this.critique,
    this.error,
  });

  factory MemberCritique.fromJson(Map<String, dynamic> json) => MemberCritique(
    memberId: json['member_id'] as String?,
    memberName: (json['member_name'] as String?) ?? '',
    critique: (json['critique'] as String?) ?? '',
    error: json['error'] as String?,
  );
}

/// Council mode opt-in. "standard" runs gather → rank → synthesise with no
/// extra rounds. "red_team" inserts one adversarial round between Stage 1
/// and Stage 2. "deliberation" runs critique/revise up to 3 rounds.
enum CouncilMode { standard, redTeam, deliberation }

extension CouncilModeWire on CouncilMode {
  String get wire {
    switch (this) {
      case CouncilMode.standard:
        return 'standard';
      case CouncilMode.redTeam:
        return 'red_team';
      case CouncilMode.deliberation:
        return 'deliberation';
    }
  }

  String get label {
    switch (this) {
      case CouncilMode.standard:
        return 'Standard';
      case CouncilMode.redTeam:
        return 'Red team';
      case CouncilMode.deliberation:
        return 'Deliberation';
    }
  }
}

class ThreadEvent {
  final int id;
  final String threadId;
  final String eventType;
  final String actorId;
  final String actorName;
  final String? content;
  final Map<String, dynamic> metadata;
  final String createdAt;

  const ThreadEvent({
    required this.id,
    required this.threadId,
    required this.eventType,
    required this.actorId,
    required this.actorName,
    this.content,
    required this.metadata,
    required this.createdAt,
  });

  factory ThreadEvent.fromJson(Map<String, dynamic> json) {
    return ThreadEvent(
      id: json['id'] as int,
      threadId: json['thread_id'] as String,
      eventType: json['event_type'] as String,
      actorId: json['actor_id'] as String,
      actorName: json['actor_name'] as String,
      content: json['content'] as String?,
      metadata: Map<String, dynamic>.from(
        (json['metadata'] as Map<dynamic, dynamic>?) ?? {},
      ),
      createdAt: json['created_at'] as String,
    );
  }
}

class Template {
  final String id;
  final String name;
  final String description;
  final String councilType;
  final int memberCount;

  const Template({
    required this.id,
    required this.name,
    required this.description,
    required this.councilType,
    required this.memberCount,
  });

  factory Template.fromJson(Map<String, dynamic> json) {
    return Template(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      councilType: json['council_type'] as String,
      memberCount: (json['member_count'] as int?) ?? 0,
    );
  }
}

class CreateCouncilResponse {
  final String sessionId;
  final String threadId;
  final String status;

  const CreateCouncilResponse({
    required this.sessionId,
    required this.threadId,
    required this.status,
  });

  factory CreateCouncilResponse.fromJson(Map<String, dynamic> json) {
    return CreateCouncilResponse(
      sessionId: json['session_id'] as String,
      threadId: json['thread_id'] as String,
      status: json['status'] as String,
    );
  }
}

class ContributeResponse {
  final String sessionId;
  final int contributionsReceived;
  final int quorum;
  final bool quorumMet;

  const ContributeResponse({
    required this.sessionId,
    required this.contributionsReceived,
    required this.quorum,
    required this.quorumMet,
  });

  factory ContributeResponse.fromJson(Map<String, dynamic> json) {
    return ContributeResponse(
      sessionId: json['session_id'] as String,
      contributionsReceived: (json['contributions_received'] as int?) ?? 0,
      quorum: (json['quorum'] as int?) ?? 0,
      quorumMet: (json['quorum_met'] as bool?) ?? false,
    );
  }
}

class ChatResponse {
  final String answer;
  final List<dynamic> sources;

  const ChatResponse({required this.answer, required this.sources});

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      answer: json['answer'] as String,
      sources: (json['sources'] as List<dynamic>?) ?? [],
    );
  }
}

// ─── Notifications (B10 / W9 / F3) ────────────────────────────────────────

class NotificationPreferences {
  final bool emailEnabled;
  final String? emailAddress;
  final bool ntfyEnabled;
  // FCM/APNs gate — independent of `ntfy_enabled` since async-councils
  // Slice 5. The old wiring conflated them (turning off ntfy silently
  // killed mobile push too); now this is the canonical mobile-push
  // switch. Defaults false so opt-in is explicit.
  final bool pushEnabled;
  final String updatedAt;

  const NotificationPreferences({
    required this.emailEnabled,
    this.emailAddress,
    required this.ntfyEnabled,
    this.pushEnabled = false,
    required this.updatedAt,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      emailEnabled: (json['email_enabled'] as bool?) ?? false,
      emailAddress: json['email_address'] as String?,
      ntfyEnabled: (json['ntfy_enabled'] as bool?) ?? false,
      // Backend defaults this to false on the row when not yet set; the
      // ?? guard also covers Synapse OSS responses that don't have the
      // field at all (parity-friendly).
      pushEnabled: (json['push_enabled'] as bool?) ?? false,
      updatedAt: (json['updated_at'] as String?) ?? '',
    );
  }
}

class DeviceToken {
  final String id;
  final String tokenType;
  final String token;
  final String? deviceLabel;
  final String createdAt;

  const DeviceToken({
    required this.id,
    required this.tokenType,
    required this.token,
    this.deviceLabel,
    required this.createdAt,
  });

  factory DeviceToken.fromJson(Map<String, dynamic> json) {
    return DeviceToken(
      id: json['id'] as String,
      tokenType: json['token_type'] as String,
      token: json['token'] as String,
      deviceLabel: json['device_label'] as String?,
      createdAt: (json['created_at'] as String?) ?? '',
    );
  }
}

/// Recently-active workspace principal — populates the chat-input
/// @mention picker on async-council creation. Cerebro aggregates from
/// audit_logs + councils.created_by; Synapse OSS doesn't expose this
/// yet (clients handle the 404 by falling through to email-invite mode).
class WorkspaceUser {
  /// Stable principal id, e.g. "user:alice". Used as the council member
  /// id when this user is added to a roster — round-trips verbatim.
  final String id;

  /// Prefix-stripped label for UI ("alice"). Same value the picker
  /// inserts into the textarea after a selection.
  final String displayName;

  /// ISO 8601 timestamp; null when the principal has never been seen.
  final String? lastSeenAt;

  const WorkspaceUser({
    required this.id,
    required this.displayName,
    this.lastSeenAt,
  });

  factory WorkspaceUser.fromJson(Map<String, dynamic> json) => WorkspaceUser(
    id: json['id'] as String,
    displayName: json['display_name'] as String,
    lastSeenAt: json['last_seen_at'] as String?,
  );
}

/// A human collected from the @mention picker before the user submits a
/// chat message. Either `sub` (workspace user) OR `email` (external
/// invitee) is set, never both — picker keeps them disjoint at the type
/// level. Becomes the `humans` arg threaded into the chat-with-tools
/// `streamChatMessage` call (Cerebro merges it into the
/// `synapse_council_start` tool's `humans` parameter server-side).
sealed class PendingHuman {
  final String name;
  const PendingHuman({required this.name});

  Map<String, dynamic> toJson();

  /// Stable dedupe key for chip equality (workspace sub or downcased
  /// email). Mirrors the server-side dedupe in `Synapse.Chat.Tools`.
  String get dedupeKey;
}

class PendingHumanWorkspace extends PendingHuman {
  final String sub;
  const PendingHumanWorkspace({required super.name, required this.sub});

  @override
  Map<String, dynamic> toJson() => {'name': name, 'sub': sub};

  @override
  String get dedupeKey => 'sub:$sub';
}

class PendingHumanInvite extends PendingHuman {
  final String email;
  const PendingHumanInvite({required super.name, required this.email});

  @override
  Map<String, dynamic> toJson() => {'name': name, 'email': email};

  @override
  String get dedupeKey => 'email:${email.toLowerCase()}';
}

class FeedItem {
  /// One of: verdict_ready, pending_approval, in_progress,
  /// summon_requested, awaited_contribution.
  /// `awaited_contribution` is Cerebro-only and added by async councils
  /// Slice 3.5 — surfaces when the current user is a `member_type:
  /// "human"` member of a parked council.
  final String type;
  final String councilId;
  final String question;
  final String? verdict;
  final String? confidenceLabel;
  final double? consensusScore;
  final String occurredAt;

  const FeedItem({
    required this.type,
    required this.councilId,
    required this.question,
    this.verdict,
    this.confidenceLabel,
    this.consensusScore,
    required this.occurredAt,
  });

  factory FeedItem.fromJson(Map<String, dynamic> json) {
    return FeedItem(
      type: json['type'] as String,
      councilId: json['council_id'] as String,
      question: json['question'] as String,
      verdict: json['verdict'] as String?,
      confidenceLabel: json['confidence_label'] as String?,
      consensusScore: (json['consensus_score'] as num?)?.toDouble(),
      occurredAt: (json['occurred_at'] as String?) ?? '',
    );
  }
}

// ─── Backend metadata (X-2) ──────────────────────────────────────────────

class BackendInfo {
  /// "synapse" or "cerebro"
  final String backend;
  final String version;

  /// "jwt_hs256" | "jwt_oidc" | "local"
  final String authMode;
  final bool multiTenant;
  final bool billing;

  /// Real-time transport: "centrifugo" (Synapse OSS) or "phoenix" (Cerebro).
  /// SDK adapters and non-SDK clients pick the transport library on this
  /// field. See cerebro/docs/_design/realtime.md §6.
  final String realtime;

  /// OIDC issuer URL (present when authMode == "jwt_oidc")
  final String? oidcIssuer;

  /// OIDC client ID (present when authMode == "jwt_oidc")
  final String? oidcClientId;

  const BackendInfo({
    required this.backend,
    required this.version,
    required this.authMode,
    required this.multiTenant,
    required this.billing,
    required this.realtime,
    this.oidcIssuer,
    this.oidcClientId,
  });

  factory BackendInfo.fromJson(Map<String, dynamic> json) {
    final oidc = json['oidc'] as Map<String, dynamic>?;
    return BackendInfo(
      backend: json['backend'] as String,
      version: (json['version'] as String?) ?? '',
      authMode: (json['auth_mode'] as String?) ?? 'jwt_hs256',
      multiTenant: (json['multi_tenant'] as bool?) ?? false,
      billing: (json['billing'] as bool?) ?? false,
      // Fall back to "centrifugo" when the server is old enough to predate
      // this field — that's the historical (Synapse OSS) default.
      realtime: (json['realtime'] as String?) ?? 'centrifugo',
      oidcIssuer: oidc?['issuer'] as String?,
      oidcClientId: oidc?['client_id'] as String?,
    );
  }
}

// ─── Memory hits (W4 / F-extend) ─────────────────────────────────────────

class MemoryHit {
  final String memoryId;
  final String content;
  final double score;
  final String bankId;
  final List<String> tags;

  const MemoryHit({
    required this.memoryId,
    required this.content,
    required this.score,
    required this.bankId,
    required this.tags,
  });

  factory MemoryHit.fromJson(Map<String, dynamic> json) {
    return MemoryHit(
      memoryId: (json['memory_id'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      score: ((json['score'] as num?) ?? 0).toDouble(),
      bankId: (json['bank_id'] as String?) ?? '',
      tags: ((json['tags'] as List?) ?? []).map((e) => e.toString()).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat-with-tools (Mode 4) — free-standing chat sessions with tool calling.
// See docs/_design/chat.md §4a. Wire contract:
// priv/contracts/chat-api-v1.openapi.json.
// ---------------------------------------------------------------------------

class AgentConfig {
  final String? model;
  final List<String> tools;

  const AgentConfig({this.model, this.tools = const []});

  factory AgentConfig.fromJson(Map<String, dynamic> json) {
    return AgentConfig(
      model: json['model'] as String?,
      tools: ((json['tools'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (model != null) 'model': model,
    'tools': tools,
  };
}

class ChatSession {
  final String id;
  final String threadId;
  final String title;
  final String status; // "active" | "archived"
  final AgentConfig agentConfig;
  final String createdAt;
  final String updatedAt;

  const ChatSession({
    required this.id,
    required this.threadId,
    required this.title,
    required this.status,
    required this.agentConfig,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isArchived => status == 'archived';

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      threadId: json['thread_id'] as String,
      title: (json['title'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'active',
      agentConfig: AgentConfig.fromJson(
        (json['agent_config'] as Map<String, dynamic>?) ?? const {},
      ),
      createdAt: json['created_at'] as String,
      updatedAt:
          (json['updated_at'] as String?) ?? json['created_at'] as String,
    );
  }
}

class ListChatSessionsResponse {
  final List<ChatSession> data;
  final String? nextBeforeId;

  const ListChatSessionsResponse({required this.data, this.nextBeforeId});

  factory ListChatSessionsResponse.fromJson(Map<String, dynamic> json) {
    return ListChatSessionsResponse(
      data: ((json['data'] as List?) ?? const [])
          .map((e) => ChatSession.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextBeforeId: json['next_before_id'] as String?,
    );
  }
}

/// Sealed hierarchy over the SSE event types defined in chat.md §4a.
///
/// Use `switch (event)` to dispatch — exhaustive over the six concrete
/// subtypes. `fromJson` returns `null` for unknown / malformed payloads so
/// the caller can skip them silently (matches the OpenAPI contract: the
/// receiver MUST tolerate unknown event types for forward compatibility).
sealed class ChatSseEvent {
  const ChatSseEvent();

  static ChatSseEvent? fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String) return null;
    return switch (type) {
      'session_started' => SessionStartedEvent.fromJson(json),
      'token' => TokenEvent.fromJson(json),
      'tool_call' => ToolCallEvent.fromJson(json),
      'tool_result' => ToolResultEvent.fromJson(json),
      'message_complete' => MessageCompleteEvent.fromJson(json),
      'error' => ChatErrorEvent.fromJson(json),
      _ => null,
    };
  }
}

class SessionStartedEvent extends ChatSseEvent {
  final String sessionId;
  final String threadId;
  const SessionStartedEvent({required this.sessionId, required this.threadId});
  factory SessionStartedEvent.fromJson(Map<String, dynamic> j) =>
      SessionStartedEvent(
        sessionId: j['session_id'] as String,
        threadId: j['thread_id'] as String,
      );
}

class TokenEvent extends ChatSseEvent {
  final String content;
  const TokenEvent({required this.content});
  factory TokenEvent.fromJson(Map<String, dynamic> j) =>
      TokenEvent(content: (j['content'] as String?) ?? '');
}

class ToolCallEvent extends ChatSseEvent {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  const ToolCallEvent({
    required this.id,
    required this.name,
    required this.arguments,
  });
  factory ToolCallEvent.fromJson(Map<String, dynamic> j) => ToolCallEvent(
    id: j['id'] as String,
    name: j['name'] as String,
    arguments: Map<String, dynamic>.from(
      (j['arguments'] as Map<dynamic, dynamic>?) ?? const {},
    ),
  );
}

class ToolResultEvent extends ChatSseEvent {
  final String toolCallId;
  final Object? result;
  final String? error;
  const ToolResultEvent({required this.toolCallId, this.result, this.error});
  factory ToolResultEvent.fromJson(Map<String, dynamic> j) => ToolResultEvent(
    toolCallId: j['tool_call_id'] as String,
    result: j['result'],
    error: j['error'] as String?,
  );
}

class MessageCompleteEvent extends ChatSseEvent {
  final String threadId;
  const MessageCompleteEvent({required this.threadId});
  factory MessageCompleteEvent.fromJson(Map<String, dynamic> j) =>
      MessageCompleteEvent(threadId: j['thread_id'] as String);
}

class ChatErrorEvent extends ChatSseEvent {
  final String message;
  const ChatErrorEvent({required this.message});
  factory ChatErrorEvent.fromJson(Map<String, dynamic> j) =>
      ChatErrorEvent(message: (j['message'] as String?) ?? '');
}
