import 'package:flutter/material.dart';
import '../../core/api/client.dart';
import '../../core/api/models.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_tokens.dart';
import '../../widgets/verdict_card.dart';
import '../../widgets/thread_entry.dart';
import '../../widgets/directive_input.dart';

class VerdictChatScreen extends StatefulWidget {
  final String sessionId;
  final SynapseApiClient client;

  const VerdictChatScreen({
    super.key,
    required this.sessionId,
    required this.client,
  });

  @override
  State<VerdictChatScreen> createState() => _VerdictChatScreenState();
}

class _VerdictChatScreenState extends State<VerdictChatScreen> {
  CouncilDetail? _council;
  String? _threadId;
  List<ThreadEvent> _events = [];
  final List<ThreadEvent> _chatHistory = [];
  final ScrollController _scrollController = ScrollController();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final council = await widget.client.getCouncil(widget.sessionId);
      final threadId = await widget.client.getCouncilThreadId(
        council.sessionId,
      );
      final events = await widget.client.listEvents(threadId);
      if (mounted) {
        setState(() {
          _council = council;
          _threadId = threadId;
          _events = events;
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

  Future<void> _handleChat(String message) async {
    final userEvent = ThreadEvent(
      id: DateTime.now().millisecondsSinceEpoch,
      threadId: _threadId ?? widget.sessionId,
      eventType: 'user_message',
      actorId: 'user',
      actorName: 'User',
      content: message,
      metadata: const {},
      createdAt: DateTime.now().toIso8601String(),
    );
    setState(() => _chatHistory.add(userEvent));

    try {
      final response = await widget.client.chatWithVerdict(
        widget.sessionId,
        message,
      );
      final answerEvent = ThreadEvent(
        id: DateTime.now().millisecondsSinceEpoch + 1,
        threadId: _threadId ?? widget.sessionId,
        eventType: 'member_response',
        actorId: 'assistant',
        actorName: 'Assistant',
        content: response.answer,
        metadata: const {},
        createdAt: DateTime.now().toIso8601String(),
      );
      if (mounted) {
        setState(() => _chatHistory.add(answerEvent));
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final council = _council;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return SynErrorState(
        title: 'Could not load verdict chat',
        message: _error!,
        onRetry: _load,
      );
    }
    return Column(
      children: [
        if (council != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SynSpacing.xl,
              SynSpacing.lg,
              SynSpacing.xl,
              SynSpacing.sm,
            ),
            child: VerdictCard(
              verdict: council.verdict,
              consensusScore: council.consensusScore,
              confidenceLabel: council.confidenceLabel,
              dissentDetected: council.dissentDetected,
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(
              SynSpacing.xl,
              SynSpacing.sm,
              SynSpacing.xl,
              SynSpacing.lg,
            ),
            itemCount: _events.length + _chatHistory.length,
            itemBuilder: (context, index) {
              final allItems = [..._events, ..._chatHistory];
              return ThreadEntry(event: allItems[index]);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SynSpacing.xl,
            0,
            SynSpacing.xl,
            SynSpacing.lg,
          ),
          child: DirectiveInput(onSend: _handleChat),
        ),
      ],
    );
  }
}
