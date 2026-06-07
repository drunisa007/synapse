import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api/client.dart';
import '../../core/api/models.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_tokens.dart';

/// Mode 4 list screen — free-standing chat sessions ("Assistant").
///
/// Mirrors apps/web/src/routes/chat/sessions/+page.svelte. Filters by
/// status (active / archived / all), supports create + archive, links into
/// the detail screen.
class ChatSessionsScreen extends StatefulWidget {
  final SynapseApiClient client;

  const ChatSessionsScreen({super.key, required this.client});

  @override
  State<ChatSessionsScreen> createState() => _ChatSessionsScreenState();
}

class _ChatSessionsScreenState extends State<ChatSessionsScreen> {
  List<ChatSession> _sessions = const [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'active';
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await widget.client.listChatSessions(
        status: _statusFilter,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _sessions = resp.data;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _startNew() async {
    setState(() => _creating = true);
    try {
      final session = await widget.client.createChatSession(title: 'New chat');
      if (!mounted) return;
      context.push('/chat/sessions/${session.id}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _creating = false;
      });
      return;
    }
    if (mounted) setState(() => _creating = false);
  }

  Future<void> _archive(ChatSession s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive this chat?'),
        content: const Text('You can still view it under "Archived".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.client.archiveChatSession(s.id);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  String _relative(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 30) return '${diff.inDays}d ago';
      return DateFormat.yMMMd().format(dt);
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SynSpacing.xl,
            SynSpacing.lg,
            SynSpacing.xl,
            SynSpacing.md,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 860;
              final filter = SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'active', label: Text('Active')),
                  ButtonSegment(value: 'archived', label: Text('Archived')),
                  ButtonSegment(value: 'all', label: Text('All')),
                ],
                selected: {_statusFilter},
                onSelectionChanged: (sel) {
                  setState(() => _statusFilter = sel.first);
                  _load();
                },
              );
              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                  ),
                  const SizedBox(width: SynSpacing.sm),
                  FilledButton.icon(
                    onPressed: _creating ? null : _startNew,
                    icon: _creating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add, size: 16),
                    label: const Text('New chat'),
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    filter,
                    const SizedBox(height: SynSpacing.sm),
                    actions,
                  ],
                );
              }
              return Row(children: [filter, const Spacer(), actions]);
            },
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return SynErrorState(
        title: 'Could not load chats',
        message: _error!,
        onRetry: _load,
      );
    }
    if (_sessions.isEmpty) {
      return SynEmptyState(
        icon: Icons.forum_outlined,
        title: _statusFilter == 'archived'
            ? 'No archived chats'
            : 'No chats yet.',
        message: _statusFilter == 'archived'
            ? 'Archived assistant threads will appear here.'
            : 'Start a thread when you want a tool-using assistant outside a council.',
        action: FilledButton(
          onPressed: _creating ? null : _startNew,
          child: const Text('Start your first chat'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          SynSpacing.xl,
          SynSpacing.sm,
          SynSpacing.xl,
          SynSpacing.xl,
        ),
        itemCount: _sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: SynSpacing.sm),
        itemBuilder: (ctx, i) {
          final s = _sessions[i];
          return SynSurface(
            padding: const EdgeInsets.symmetric(
              horizontal: SynSpacing.lg,
              vertical: SynSpacing.md,
            ),
            onTap: () => context.push('/chat/sessions/${s.id}'),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: SynColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(SynRadii.md),
                    border: Border.all(
                      color: SynColors.primary.withValues(alpha: 0.28),
                    ),
                  ),
                  child: const Icon(
                    Icons.forum_outlined,
                    size: 18,
                    color: SynColors.primary,
                  ),
                ),
                const SizedBox(width: SynSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title.isEmpty ? 'Untitled chat' : s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: SynSpacing.xs),
                      Text(
                        'Updated ${_relative(s.updatedAt)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SynColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SynSpacing.md),
                if (s.isArchived)
                  const Chip(
                    label: Text('archived'),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  SynIconButton(
                    icon: Icons.archive_outlined,
                    tooltip: 'Archive',
                    onPressed: () => _archive(s),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
