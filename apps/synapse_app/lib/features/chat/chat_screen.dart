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

  const ChatScreen({
    super.key,
    required this.sessionId,
    required this.threadId,
    required this.councilStatus,
    required this.client,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ThreadEvent> _events = [];
  final ScrollController _scrollController = ScrollController();
  SynapseRealtimeClient? _realtimeClient;
  StreamSubscription<NormalizedRealtimeEvent>? _subscription;
  bool _loading = true;
  String? _error;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _status = widget.councilStatus;
    _loadEvents();
    _connectRealtime();
  }

  Future<void> _loadEvents() async {
    try {
      final events = await widget.client.listEvents(widget.threadId);
      if (mounted) {
        setState(() {
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
      return SynErrorState(message: _error!);
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
        Expanded(
          child: _events.isEmpty
              ? const SynEmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No thread events yet',
                  message: 'Events will appear when the council starts.',
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(SynSpacing.md),
                  itemCount: _events.length + (_status == 'closed' ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_status == 'closed' && index == _events.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: SynSpacing.md),
                        child: Row(
                          children: [
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: SynSpacing.sm,
                              ),
                              child: Text(
                                'Council concluded',
                                style: TextStyle(
                                  color: SynColors.textFaint,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                      );
                    }
                    return ThreadEntry(event: _events[index]);
                  },
                ),
        ),
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
