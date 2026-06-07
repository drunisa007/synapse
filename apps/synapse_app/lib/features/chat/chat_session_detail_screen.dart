import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/client.dart';
import '../../core/api/models.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_tokens.dart';
import '../../widgets/mention_picker.dart';

/// Mode 4 detail screen — free-standing chat session with SSE streaming.
///
/// Mirrors apps/web/src/routes/chat/sessions/[id]/+page.svelte. Loads the
/// session + past thread_events on mount, then merges live SSE events into
/// a typed list of [_LiveMessage]s as the user sends messages.
class ChatSessionDetailScreen extends StatefulWidget {
  final SynapseApiClient client;
  final String sessionId;

  const ChatSessionDetailScreen({
    super.key,
    required this.client,
    required this.sessionId,
  });

  @override
  State<ChatSessionDetailScreen> createState() =>
      _ChatSessionDetailScreenState();
}

/// One renderable item in the in-progress chat turn. Variants line up with
/// the SSE event types the agent emits.
sealed class _LiveMessage {}

class _UserMsg extends _LiveMessage {
  final String content;
  _UserMsg(this.content);
}

class _AssistantMsg extends _LiveMessage {
  String content = '';
  bool streaming = true;
}

class _ToolMsg extends _LiveMessage {
  final String id;
  final String name;
  final Map<String, dynamic> args;
  Object? result;
  String? error;
  _ToolMsg({required this.id, required this.name, required this.args});
}

class _ChatSessionDetailScreenState extends State<ChatSessionDetailScreen> {
  ChatSession? _session;
  List<ThreadEvent> _history = const [];
  bool _loading = true;
  String? _loadError;

  final List<_LiveMessage> _live = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;
  String? _streamError;

  // ── @mention picker state (async-councils Slice 4) ─────────────────────
  // Mirrors the Svelte ChatInput logic: detect an active `@partial` token
  // under the caret, fetch matching workspace users, surface a picker
  // above the TextField, and keep the picked humans in `_pendingHumans`
  // until the next send. The fetch sequence number drops stale responses
  // when the user keeps typing.
  bool _showMentionPicker = false;
  String _mentionQuery = '';
  int? _mentionStart;
  List<WorkspaceUser> _mentionUsers = const [];
  bool _mentionLoading = false;
  int _mentionFetchSeq = 0;
  final List<PendingHuman> _pendingHumans = [];

  @override
  void initState() {
    super.initState();
    _input.addListener(_handleInputChange);
    _load();
  }

  @override
  void dispose() {
    _input.removeListener(_handleInputChange);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Walk back from the caret to find the most recent `@`, bailing on
  // whitespace. Trigger is valid only at start-of-string or after a
  // whitespace char — matches the Svelte side + the directive_input
  // semantics so they don't fight over the same `@` keystroke.
  ({int start, String query})? _activeMention(String text, int caret) {
    var i = caret - 1;
    while (i >= 0) {
      final ch = text[i];
      if (ch == '@') {
        if (i == 0 || RegExp(r'\s').hasMatch(text[i - 1])) {
          return (start: i, query: text.substring(i + 1, caret));
        }
        return null;
      }
      if (RegExp(r'\s').hasMatch(ch)) return null;
      i--;
    }
    return null;
  }

  void _handleInputChange() {
    final caret = _input.selection.baseOffset;
    final value = _input.text;
    if (caret < 0) return;
    final m = _activeMention(value, caret);
    if (m == null) {
      if (_showMentionPicker) {
        setState(() {
          _showMentionPicker = false;
          _mentionStart = null;
          _mentionQuery = '';
        });
      }
      return;
    }
    setState(() {
      _showMentionPicker = true;
      _mentionStart = m.start;
      _mentionQuery = m.query;
    });
    _loadMentionUsers(m.query);
  }

  Future<void> _loadMentionUsers(String q) async {
    setState(() => _mentionLoading = true);
    final seq = ++_mentionFetchSeq;
    try {
      final users = await widget.client.listWorkspaceUsers(q: q);
      if (!mounted || seq != _mentionFetchSeq) return;
      setState(() => _mentionUsers = users);
    } catch (_) {
      // Listing isn't critical — picker still surfaces the invite-by-email
      // row when the query parses as an address.
      if (!mounted || seq != _mentionFetchSeq) return;
      setState(() => _mentionUsers = const []);
    } finally {
      if (mounted && seq == _mentionFetchSeq) {
        setState(() => _mentionLoading = false);
      }
    }
  }

  void _handleMentionSelect(PendingHuman human) {
    // Splice the active `@partial` out and replace with a readable
    // `@Name ` token. The picker's job is the data — the surface text
    // just hints at it; the canonical source of truth is _pendingHumans
    // (which gets sent in the `humans` body field).
    final start = _mentionStart;
    if (start != null) {
      final before = _input.text.substring(0, start);
      final caret = _input.selection.baseOffset.clamp(0, _input.text.length);
      final after = _input.text.substring(caret);
      final token = '@${human.name} ';
      final newText = '$before$token$after';
      final newCaret = before.length + token.length;
      _input.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newCaret),
      );
    }

    // Dedupe by sub (workspace) or downcased email (invite) — picking the
    // same person twice in one compose is a no-op, matching the server.
    final exists = _pendingHumans.any((h) => h.dedupeKey == human.dedupeKey);
    setState(() {
      if (!exists) _pendingHumans.add(human);
      _showMentionPicker = false;
      _mentionStart = null;
      _mentionQuery = '';
    });
  }

  void _removePendingHuman(PendingHuman target) {
    setState(() => _pendingHumans.remove(target));
  }

  Future<void> _load() async {
    try {
      final session = await widget.client.getChatSession(widget.sessionId);
      final events = await widget.client.listEvents(session.threadId);
      if (!mounted) return;
      setState(() {
        _session = session;
        _history = events;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final content = _input.text.trim();
    if (content.isEmpty || _sending || _session == null) return;
    // Snapshot + clear pending humans before clearing the text — the
    // backend dedupes, but we don't want a slow stream to keep the same
    // chips around for the next turn.
    final humans = List<PendingHuman>.of(_pendingHumans);
    _input.clear();
    setState(() {
      _pendingHumans.clear();
      _showMentionPicker = false;
    });
    await _runTurn(
      userBubble: content,
      stream: widget.client.streamChatMessage(
        widget.sessionId,
        content,
        humans: humans,
      ),
    );
  }

  /// Drive any SSE stream (send / edit / regenerate) through the live
  /// message reducer, applying the documented error semantics (absence of
  /// `message_complete` → treated as failure).
  Future<void> _runTurn({
    required String? userBubble,
    required Stream<ChatSseEvent> stream,
  }) async {
    if (_session == null) return;
    setState(() {
      _streamError = null;
      _sending = true;
      if (userBubble != null) _live.add(_UserMsg(userBubble));
      _live.add(_AssistantMsg());
    });
    _scrollToBottom();

    try {
      await for (final evt in stream) {
        if (!mounted) return;
        setState(() => _apply(evt));
        _scrollToBottom();
      }
      if (mounted) {
        final last = _live.lastOrNull;
        if (last is _AssistantMsg && last.streaming) {
          setState(() {
            last.streaming = false;
            _streamError ??= 'stream ended unexpectedly (no message_complete)';
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _streamError = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // --- edit / regenerate / fork --------------------------------------------

  Future<void> _promptEdit(ThreadEvent original) async {
    final controller = TextEditingController(text: original.content ?? '');
    final newContent = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          minLines: 2,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save & resend'),
          ),
        ],
      ),
    );
    if (newContent == null || newContent.isEmpty) return;
    await _runTurn(
      userBubble: newContent,
      stream: widget.client.editChatMessage(
        widget.sessionId,
        original.id,
        newContent,
      ),
    );
  }

  Future<void> _regenerate(ThreadEvent reflection) async {
    await _runTurn(
      // No new user bubble — we're re-running the existing user message.
      userBubble: null,
      stream: widget.client.regenerateChatMessage(
        widget.sessionId,
        reflection.id,
      ),
    );
  }

  Future<void> _fork(ThreadEvent at) async {
    try {
      final child = await widget.client.forkChatSession(
        widget.sessionId,
        at.id,
      );
      if (!mounted) return;
      context.go('/chat/sessions/${child.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _streamError = e.message);
    }
  }

  void _apply(ChatSseEvent evt) {
    switch (evt) {
      case SessionStartedEvent _:
        // No-op: the placeholder bubbles are already on screen.
        break;
      case TokenEvent e:
        final last = _live.lastOrNull;
        if (last is _AssistantMsg) {
          last.content += e.content;
        }
      case ToolCallEvent e:
        // Tool calls render *before* the streaming assistant message —
        // the assistant's text typically continues after the tool result.
        final assistantIdx = _live.indexWhere(
          (m) => m is _AssistantMsg && m.streaming,
        );
        final tool = _ToolMsg(id: e.id, name: e.name, args: e.arguments);
        if (assistantIdx == -1) {
          _live.add(tool);
        } else {
          _live.insert(assistantIdx, tool);
        }
      case ToolResultEvent e:
        for (final m in _live) {
          if (m is _ToolMsg && m.id == e.toolCallId) {
            m.result = e.result;
            m.error = e.error;
            break;
          }
        }
      case MessageCompleteEvent _:
        final last = _live.lastOrNull;
        if (last is _AssistantMsg) {
          last.streaming = false;
        }
      case ChatErrorEvent e:
        _streamError = e.message;
    }
  }

  void _scrollToBottom() {
    // Defer to next frame so the new widget is laid out first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return SynErrorState(
        title: 'Could not load chat',
        message: _loadError!,
        onRetry: _load,
      );
    }
    final s = _session!;
    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          SynSurface(
            margin: const EdgeInsets.fromLTRB(
              SynSpacing.xl,
              SynSpacing.lg,
              SynSpacing.xl,
              SynSpacing.sm,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: SynSpacing.lg,
              vertical: SynSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.title.isEmpty ? 'Untitled chat' : s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: SynSpacing.md),
                if (s.isArchived) const Chip(label: Text('archived')),
                const SizedBox(width: SynSpacing.sm),
                Text(
                  s.agentConfig.model ?? 'default model',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SynColors.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                SynSpacing.xl,
                SynSpacing.sm,
                SynSpacing.xl,
                SynSpacing.lg,
              ),
              children: [
                ..._history.map(_renderHistoryEvent),
                ..._live.map(_renderLive),
                if (_streamError != null)
                  SynNotice(
                    icon: Icons.error_outline,
                    title: 'Stream failed',
                    message: _streamError!,
                    color: SynColors.red,
                  ),
              ],
            ),
          ),
          SafeArea(
            child: SynSurface(
              margin: const EdgeInsets.fromLTRB(
                SynSpacing.xl,
                0,
                SynSpacing.xl,
                SynSpacing.lg,
              ),
              padding: const EdgeInsets.all(SynSpacing.md),
              color: SynColors.chrome,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_showMentionPicker)
                    MentionPicker(
                      query: _mentionQuery,
                      users: _mentionUsers,
                      loading: _mentionLoading,
                      onSelect: _handleMentionSelect,
                    ),
                  if (_pendingHumans.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: SynSpacing.sm),
                      child: Wrap(
                        spacing: SynSpacing.sm,
                        runSpacing: SynSpacing.xs,
                        children: _pendingHumans
                            .map(
                              (h) => _PendingHumanChip(
                                human: h,
                                onRemove: () => _removePendingHuman(h),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          enabled: !s.isArchived && !_sending,
                          decoration: InputDecoration(
                            hintText: s.isArchived
                                ? 'This chat is archived'
                                : 'Type a message...',
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: SynSpacing.sm),
                      SynIconButton(
                        icon: _sending ? Icons.more_horiz : Icons.send,
                        tooltip: 'Send',
                        onPressed: (s.isArchived || _sending) ? null : _send,
                        selected: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _renderHistoryEvent(ThreadEvent e) {
    final isTool = e.eventType == 'tool_call' || e.eventType == 'tool_result';
    final isUser = e.eventType == 'user_message';
    final isReflection = e.eventType == 'reflection';
    final canEdit = isUser && _session?.isArchived != true && !_sending;
    final canRegen = isReflection && _session?.isArchived != true && !_sending;
    final canFork = !_sending;
    return SynSurface(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      color: isUser
          ? SynColors.primary.withValues(alpha: 0.10)
          : isTool
          ? SynColors.amber.withValues(alpha: 0.08)
          : SynColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.eventType.toUpperCase(),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: SynColors.textFaint),
                ),
              ),
              if (canEdit)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Edit message',
                  onPressed: () => _promptEdit(e),
                ),
              if (canRegen) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Regenerate response',
                  onPressed: () => _regenerate(e),
                ),
              ],
              if (canFork) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.call_split, size: 16),
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Fork from here',
                  onPressed: () => _fork(e),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            e.content ?? '',
            style: isTool ? const TextStyle(fontFamily: 'monospace') : null,
          ),
        ],
      ),
    );
  }

  Widget _renderLive(_LiveMessage m) {
    if (m is _UserMsg) {
      return _bubble(label: 'YOU', body: m.content, tint: Colors.indigo);
    }
    if (m is _AssistantMsg) {
      return _bubble(
        label: 'ASSISTANT',
        body: m.content,
        streaming: m.streaming,
      );
    }
    final tool = m as _ToolMsg;
    final args = jsonEncode(tool.args);
    String? resultStr;
    if (tool.error != null) {
      resultStr = 'error: ${tool.error}';
    } else if (tool.result != null) {
      resultStr = tool.result is String
          ? tool.result as String
          : jsonEncode(tool.result);
    }
    return _bubble(
      label: 'TOOL · ${tool.name}',
      body: 'args: $args${resultStr == null ? "" : "\n→ $resultStr"}',
      tint: Colors.amber,
      mono: true,
    );
  }

  Widget _bubble({
    required String label,
    required String body,
    Color? tint,
    bool mono = false,
    bool streaming = false,
  }) {
    return SynSurface(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      color: (tint ?? SynColors.surfaceRaised).withValues(alpha: 0.10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: SynColors.textFaint),
              ),
              if (streaming) ...[
                const SizedBox(width: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: mono ? const TextStyle(fontFamily: 'monospace') : null,
          ),
        ],
      ),
    );
  }
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}

/// Removable chip rendered above the chat input for each @-mentioned
/// human. Visually mirrors the Svelte `<span>` chip from ChatInput.svelte
/// (indigo background, "invite" tag for external invitees, × to remove).
class _PendingHumanChip extends StatelessWidget {
  final PendingHuman human;
  final VoidCallback onRemove;

  const _PendingHumanChip({required this.human, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isInvite = human is PendingHumanInvite;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.15),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.30),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '@${human.name}',
            style: const TextStyle(
              color: Color(0xFFC7D2FE),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (isInvite) ...const [
            SizedBox(width: 4),
            Text(
              'invite',
              style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 10),
            ),
          ],
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close, size: 12, color: Color(0xFFA5B4FC)),
            ),
          ),
        ],
      ),
    );
  }
}
