import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/client.dart';
import '../../core/api/models.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_shell.dart';
import '../../ui/synapse_tokens.dart';
import '../../widgets/conflict_banner.dart';
import '../../widgets/council_status_badge.dart';
import '../../widgets/deliberation_rounds_card.dart';
import '../../widgets/verdict_card.dart';
import '../chat/chat_screen.dart';

class CouncilDetailScreen extends StatefulWidget {
  final String sessionId;
  final SynapseApiClient client;

  const CouncilDetailScreen({
    super.key,
    required this.sessionId,
    required this.client,
  });

  @override
  State<CouncilDetailScreen> createState() => _CouncilDetailScreenState();
}

class _CouncilDetailScreenState extends State<CouncilDetailScreen> {
  CouncilDetail? _council;
  bool _loading = true;
  String? _error;

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
      final council = await widget.client.getCouncil(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _council = council;
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

  Future<void> _handleApprove() async {
    try {
      await widget.client.approveCouncil(widget.sessionId);
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final council = _council;
    return SynapseWorkspaceFrame(
      selected: SynapseNavItem.councils,
      title: council == null ? 'Council' : _shortTitle(council.question),
      subtitle: council?.sessionId,
      onBack: () => context.go('/councils'),
      actions: [
        if (council?.status == 'closed')
          OutlinedButton.icon(
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: const Text('Verdict chat'),
            onPressed: () =>
                context.push('/councils/${widget.sessionId}/verdict'),
          ),
        if (council?.status == 'closed') const SizedBox(width: SynSpacing.sm),
        SynIconButton(
          icon: Icons.refresh,
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
        ),
      ],
      body: _buildBody(council),
    );
  }

  Widget _buildBody(CouncilDetail? council) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return SynErrorState(message: _error!, onRetry: _load);
    }
    if (council == null) {
      return const SynEmptyState(
        icon: Icons.search_off_outlined,
        title: 'Council not found',
        message: 'The selected council is not available.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        if (!wide) {
          return _NarrowLayout(
            council: council,
            onApprove: _handleApprove,
            client: widget.client,
          );
        }

        return Padding(
          padding: const EdgeInsets.all(SynSpacing.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 360,
                child: _MetaPanel(council: council, onApprove: _handleApprove),
              ),
              const SizedBox(width: SynSpacing.lg),
              Expanded(
                child: SynSurface(
                  padding: EdgeInsets.zero,
                  color: SynColors.surfaceMuted,
                  child: _CouncilThreadPane(
                    sessionId: council.sessionId,
                    councilStatus: council.status,
                    client: widget.client,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _shortTitle(String question) {
    if (question.length <= 72) return question;
    return '${question.substring(0, 72)}...';
  }
}

class _MetaPanel extends StatelessWidget {
  final CouncilDetail council;
  final VoidCallback onApprove;

  const _MetaPanel({required this.council, required this.onApprove});

  @override
  Widget build(BuildContext context) {
    return SynSurface(
      padding: EdgeInsets.zero,
      color: SynColors.surface,
      child: ListView(
        padding: const EdgeInsets.all(SynSpacing.lg),
        children: [
          Row(
            children: [
              CouncilStatusBadge(status: council.status),
              const Spacer(),
              Text(
                _formatDate(council.createdAt),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: SynColors.textFaint),
              ),
            ],
          ),
          const SizedBox(height: SynSpacing.lg),
          SelectableText(
            council.question,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(height: 1.35),
          ),
          const SizedBox(height: SynSpacing.lg),
          if (council.status == 'failed')
            SynNotice(
              icon: Icons.error_outline,
              title: 'Council failed',
              message:
                  council.failureReason ??
                  'The backend marked this council as failed.',
              color: SynColors.red,
            ),
          if (council.conflictDetected) ...[
            if (council.status == 'failed')
              const SizedBox(height: SynSpacing.md),
            ConflictBanner(
              conflictMetadata: council.conflictMetadata,
              councilStatus: council.status,
              onApprove: council.status == 'pending_approval'
                  ? onApprove
                  : null,
            ),
          ],
          if (council.status == 'pending_approval' &&
              !council.conflictDetected) ...[
            if (council.status == 'failed')
              const SizedBox(height: SynSpacing.md),
            SynNotice(
              icon: Icons.rule_folder_outlined,
              title: 'Needs approval',
              message:
                  'Review the generated verdict before closing this council.',
              color: SynColors.amber,
              action: FilledButton(
                onPressed: onApprove,
                child: const Text('Approve'),
              ),
            ),
          ],
          if (council.status == 'waiting_contributions') ...[
            const SizedBox(height: SynSpacing.md),
            SynNotice(
              icon: Icons.groups_2_outlined,
              title: 'Awaiting contributions',
              message:
                  '${council.contributionsReceived} of ${council.quorum ?? '?'} required.',
              color: SynColors.magenta,
            ),
          ],
          const SizedBox(height: SynSpacing.lg),
          SynSurface(
            color: SynColors.surfaceMuted,
            child: Column(
              children: [
                SynMetaRow(label: 'Type', value: council.councilType),
                const SizedBox(height: SynSpacing.sm),
                SynMetaRow(
                  label: 'Confidence',
                  value: council.confidenceLabel ?? 'Not available',
                ),
                const SizedBox(height: SynSpacing.sm),
                SynMetaRow(
                  label: 'Consensus',
                  value: council.consensusScore == null
                      ? 'Not available'
                      : '${(council.consensusScore! * 100).round()}%',
                ),
              ],
            ),
          ),
          if (council.members.isNotEmpty) ...[
            const SizedBox(height: SynSpacing.lg),
            Text('Members', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: SynSpacing.sm),
            ...council.members.map((member) => _MemberTile(member: member)),
          ],
          if (council.verdict != null) ...[
            const SizedBox(height: SynSpacing.lg),
            VerdictCard(
              verdict: council.verdict,
              consensusScore: council.consensusScore,
              confidenceLabel: council.confidenceLabel,
              dissentDetected: council.dissentDetected,
            ),
          ],
          if (council.deliberationRounds.isNotEmpty) ...[
            const SizedBox(height: SynSpacing.lg),
            DeliberationRoundsCard(rounds: council.deliberationRounds),
          ],
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }
}

class _MemberTile extends StatelessWidget {
  final Map<String, dynamic> member;

  const _MemberTile({required this.member});

  @override
  Widget build(BuildContext context) {
    final name = member['name']?.toString() ?? 'Unknown';
    final role = member['role']?.toString();
    final model = member['model_id']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: SynSpacing.sm),
      padding: const EdgeInsets.all(SynSpacing.md),
      decoration: BoxDecoration(
        color: SynColors.surfaceMuted,
        borderRadius: BorderRadius.circular(SynRadii.lg),
        border: Border.all(color: SynColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.person_outline,
            size: 18,
            color: SynColors.textMuted,
          ),
          const SizedBox(width: SynSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (role != null || model != null)
                  Text(
                    role ?? model!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _NarrowLayout extends StatelessWidget {
  final CouncilDetail council;
  final VoidCallback onApprove;
  final SynapseApiClient client;

  const _NarrowLayout({
    required this.council,
    required this.onApprove,
    required this.client,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Thread'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(SynSpacing.lg),
                  child: _MetaPanel(council: council, onApprove: onApprove),
                ),
                Padding(
                  padding: const EdgeInsets.all(SynSpacing.lg),
                  child: SynSurface(
                    padding: EdgeInsets.zero,
                    color: SynColors.surfaceMuted,
                    child: _CouncilThreadPane(
                      sessionId: council.sessionId,
                      councilStatus: council.status,
                      client: client,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CouncilThreadPane extends StatelessWidget {
  final String sessionId;
  final String councilStatus;
  final SynapseApiClient client;

  const _CouncilThreadPane({
    required this.sessionId,
    required this.councilStatus,
    required this.client,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: client.getCouncilThreadId(sessionId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          return SynErrorState(
            title: 'Thread unavailable',
            message: snapshot.error?.toString() ?? 'Thread not found',
          );
        }
        return ChatScreen(
          sessionId: sessionId,
          threadId: snapshot.data!,
          councilStatus: councilStatus,
          client: client,
        );
      },
    );
  }
}
