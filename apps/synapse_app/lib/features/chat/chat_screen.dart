import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api/client.dart';
import '../../core/api/models.dart';
import '../../core/realtime/realtime_client.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_tokens.dart';
import '../../widgets/live_status_banner.dart';
import '../../widgets/thread_entry.dart';
import '../../widgets/directive_input.dart';

class ChatScreen extends StatefulWidget {
  final String sessionId;
  final String threadId;
  final String councilStatus;
  final SynapseApiClient client;
  final CouncilDetail? council;

  const ChatScreen({
    super.key,
    required this.sessionId,
    required this.threadId,
    required this.councilStatus,
    required this.client,
    this.council,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ThreadEvent> _events = [];
  final ScrollController _scrollController = ScrollController();
  SynapseRealtimeClient? _realtimeClient;
  StreamSubscription<NormalizedRealtimeEvent>? _subscription;
  CouncilDetail? _council;
  bool _loading = true;
  String? _error;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _council = widget.council;
    _status = widget.council?.status ?? widget.councilStatus;
    _loadEvents();
    if (widget.council == null) {
      _loadCouncilContext();
    }
    _connectRealtime();
  }

  Future<void> _loadCouncilContext() async {
    try {
      final council = await widget.client.getCouncil(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _council = council;
        _status = council.status;
      });
    } catch (_) {
      // Thread history can still render from durable events if council metadata
      // is unavailable.
    }
  }

  Future<void> _loadEvents() async {
    try {
      final events = await widget.client.listEvents(widget.threadId);
      events.sort((a, b) => a.id.compareTo(b.id));
      if (mounted) {
        setState(() {
          _events.clear();
          _events.addAll(events);
          _loading = false;
        });
        _scrollToBottom();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _connectRealtime() async {
    try {
      final descriptor = await widget.client.getRealtimeDescriptor();
      _realtimeClient = SynapseRealtimeClient.fromDescriptor(descriptor);
      await _realtimeClient!.connect();
      final stream = _realtimeClient!.subscribe('thread:${widget.threadId}');
      _subscription = stream.listen(_onRealtimeEvent);
    } catch (_) {
      // Realtime not critical — polling via load is fallback
    }
  }

  void _onRealtimeEvent(NormalizedRealtimeEvent event) {
    if (!mounted) return;
    try {
      final threadEvent = ThreadEvent.fromJson(event.payload);
      setState(() {
        _events.add(threadEvent);
        _events.sort((a, b) => a.id.compareTo(b.id));
        if (threadEvent.eventType == 'verdict' ||
            threadEvent.eventType == 'council_closed') {
          _status = 'closed';
        }
      });
      _scrollToBottom();
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend(String text) async {
    if (_status == 'waiting_contributions') {
      try {
        await widget.client.contribute(
          widget.sessionId,
          memberId: 'user',
          memberName: 'User',
          content: text,
        );
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    } else if (_status == 'closed') {
      try {
        final response = await widget.client.chatWithVerdict(
          widget.sessionId,
          text,
        );
        final fakeEvent = ThreadEvent(
          id: DateTime.now().millisecondsSinceEpoch,
          threadId: widget.threadId,
          eventType: 'user_message',
          actorId: 'user',
          actorName: 'User',
          content: text,
          metadata: const {},
          createdAt: DateTime.now().toIso8601String(),
        );
        final answerEvent = ThreadEvent(
          id: DateTime.now().millisecondsSinceEpoch + 1,
          threadId: widget.threadId,
          eventType: 'member_response',
          actorId: 'assistant',
          actorName: 'Assistant',
          content: response.answer,
          metadata: const {},
          createdAt: DateTime.now().toIso8601String(),
        );
        if (mounted) {
          setState(() {
            _events.add(fakeEvent);
            _events.add(answerEvent);
          });
          _scrollToBottom();
        }
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
  }

  Future<void> _handleClose() async {
    try {
      await widget.client.closeCouncil(widget.sessionId);
      if (mounted) setState(() => _status = 'closed');
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _handleApprove() async {
    try {
      await widget.client.approveCouncil(widget.sessionId);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  bool get _isReadOnly =>
      _status != 'waiting_contributions' && _status != 'closed';

  bool get _hasVerdict => _events.any((event) => event.eventType == 'verdict');

  String? get _question {
    final councilQuestion = _council?.question.trim();
    if (councilQuestion != null && councilQuestion.isNotEmpty) {
      return councilQuestion;
    }
    for (final event in _events) {
      final question = event.metadata['question']?.toString().trim();
      if (question != null && question.isNotEmpty) return question;
    }
    return null;
  }

  int? get _memberCount {
    if (_council != null) return _council!.members.length;
    for (final event in _events) {
      final count = event.metadata['member_count'];
      if (count is int) return count;
      if (count is num) return count.toInt();
    }
    return null;
  }

  Widget _buildTimeline() {
    final question = _question;
    final showConcluded = _status == 'closed' && _hasVerdict;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(SynSpacing.md),
      children: [
        if (question != null) ...[
          _ThreadQuestionCard(
            question: question,
            status: _status,
            councilType: _council?.councilType,
            memberCount: _memberCount,
          ),
          const SizedBox(height: SynSpacing.md),
        ],
        if (_events.isEmpty)
          const _WaitingForActivity()
        else
          ..._events.map((event) => ThreadEntry(event: event)),
        if (showConcluded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: SynSpacing.md),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: SynSpacing.sm),
                  child: Text(
                    'Council concluded',
                    style: TextStyle(color: SynColors.textFaint, fontSize: 11),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _realtimeClient?.disconnect();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return SynErrorState(message: _error!, onRetry: _loadEvents);
    }

    return Column(
      children: [
        LiveStatusBanner(client: widget.client, councilId: widget.sessionId),
        if (_isReadOnly && _status != 'closed')
          SynNotice(
            icon: Icons.lock_outline,
            title: 'Thread is read-only',
            message:
                'This council is currently ${_status.replaceAll('_', ' ')}.',
            color: SynColors.cyan,
          ),
        Expanded(child: _buildTimeline()),
        DirectiveInput(
          onSend: _handleSend,
          onClose: _handleClose,
          onApprove: _handleApprove,
          readOnly: _isReadOnly,
        ),
      ],
    );
  }
}

class _ThreadQuestionCard extends StatelessWidget {
  final String question;
  final String status;
  final String? councilType;
  final int? memberCount;

  const _ThreadQuestionCard({
    required this.question,
    required this.status,
    required this.councilType,
    required this.memberCount,
  });

  @override
  Widget build(BuildContext context) {
    final statusStyle = synStatusStyle(status);
    return SynSurface(
      color: SynColors.surface,
      side: const BorderSide(color: SynColors.border),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.help_outline,
                color: SynColors.primary,
                size: 18,
              ),
              const SizedBox(width: SynSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Question',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: SynColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: SynSpacing.xs),
                    SelectableText(
                      question,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SynSpacing.md),
          Wrap(
            spacing: SynSpacing.sm,
            runSpacing: SynSpacing.sm,
            children: [
              _MetaChip(
                icon: statusStyle.icon,
                label: statusStyle.label,
                color: statusStyle.color,
              ),
              if (councilType != null && councilType!.trim().isNotEmpty)
                _MetaChip(
                  icon: Icons.account_tree_outlined,
                  label: councilType!,
                  color: SynColors.textMuted,
                ),
              if (memberCount != null)
                _MetaChip(
                  icon: Icons.groups_2_outlined,
                  label: '$memberCount members',
                  color: SynColors.textMuted,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SynSpacing.sm,
        vertical: SynSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(SynRadii.pill),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: SynSpacing.xs),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingForActivity extends StatelessWidget {
  const _WaitingForActivity();

  @override
  Widget build(BuildContext context) {
    return SynSurface(
      color: SynColors.surfaceMuted,
      child: Row(
        children: [
          const Icon(
            Icons.forum_outlined,
            color: SynColors.textFaint,
            size: 20,
          ),
          const SizedBox(width: SynSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting for council activity',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: SynSpacing.xs),
                Text(
                  'Events will appear when the council starts.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: SynColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
