import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/client.dart';
import '../../core/api/models.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_tokens.dart';

const _searchBanks = ['decisions', 'precedents', 'councils'];
const _graphBanks = ['decisions', 'precedents', 'agents'];
const _compileBanks = ['decisions', 'agents'];

class MemoryScreen extends StatelessWidget {
  final SynapseApiClient apiClient;

  const MemoryScreen({super.key, required this.apiClient});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          const SynSurface(
            margin: EdgeInsets.fromLTRB(
              SynSpacing.xl,
              SynSpacing.lg,
              SynSpacing.xl,
              SynSpacing.md,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: SynSpacing.md,
              vertical: SynSpacing.sm,
            ),
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.manage_search), text: 'Search'),
                Tab(icon: Icon(Icons.psychology_alt_outlined), text: 'Reflect'),
                Tab(icon: Icon(Icons.archive_outlined), text: 'Retain'),
                Tab(icon: Icon(Icons.hub_outlined), text: 'Graph'),
                Tab(
                  icon: Icon(Icons.auto_awesome_motion_outlined),
                  text: 'Compile',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _SearchTab(apiClient: apiClient),
                _ReflectTab(apiClient: apiClient),
                _RetainTab(apiClient: apiClient),
                _GraphTab(apiClient: apiClient),
                _CompileTab(apiClient: apiClient),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchTab extends StatefulWidget {
  final SynapseApiClient apiClient;

  const _SearchTab({required this.apiClient});

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  final _queryCtrl = TextEditingController();
  String _bank = 'decisions';
  int _limit = 10;
  Future<List<MemoryHit>>? _future;

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  void _search() {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _future = widget.apiClient.searchMemory(
        query,
        bank: _bank,
        limit: _limit,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SynSurface(
          margin: const EdgeInsets.fromLTRB(
            SynSpacing.xl,
            SynSpacing.sm,
            SynSpacing.xl,
            SynSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryCtrl,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                    labelText: 'Query',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: SynSpacing.md),
              _BankDropdown(
                value: _bank,
                banks: _searchBanks,
                onChanged: (value) => setState(() => _bank = value),
              ),
              const SizedBox(width: SynSpacing.md),
              _LimitDropdown(
                value: _limit,
                values: const [5, 10, 20],
                onChanged: (value) => setState(() => _limit = value),
              ),
              const SizedBox(width: SynSpacing.md),
              FilledButton.icon(
                onPressed: _search,
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Search'),
              ),
            ],
          ),
        ),
        Expanded(child: _results()),
      ],
    );
  }

  Widget _results() {
    final future = _future;
    if (future == null) {
      return const SynEmptyState(
        icon: Icons.manage_search,
        title: 'Search memory',
        message: 'Query decisions, precedents, and council records.',
      );
    }
    return FutureBuilder<List<MemoryHit>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return SynErrorState(
            title: 'Memory search failed',
            message: snapshot.error.toString(),
            onRetry: _search,
          );
        }
        final hits = snapshot.data ?? const [];
        if (hits.isEmpty) {
          return const SynEmptyState(
            icon: Icons.search_off,
            title: 'No matches',
            message: 'Try a broader query or switch the memory bank.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            SynSpacing.xl,
            SynSpacing.sm,
            SynSpacing.xl,
            SynSpacing.xl,
          ),
          itemBuilder: (_, index) => _MemoryHitTile(hit: hits[index]),
          separatorBuilder: (_, __) => const SizedBox(height: SynSpacing.sm),
          itemCount: hits.length,
        );
      },
    );
  }
}

class _ReflectTab extends StatefulWidget {
  final SynapseApiClient apiClient;

  const _ReflectTab({required this.apiClient});

  @override
  State<_ReflectTab> createState() => _ReflectTabState();
}

class _ReflectTabState extends State<_ReflectTab> {
  final _queryCtrl = TextEditingController();
  final _maxTokensCtrl = TextEditingController();
  String _bank = 'decisions';
  bool _includeSources = true;
  MemoryReflection? _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _queryCtrl.dispose();
    _maxTokensCtrl.dispose();
    super.dispose();
  }

  Future<void> _reflect() async {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'Query is required.');
      return;
    }
    final maxTokens = _parseOptionalInt(_maxTokensCtrl.text);
    if (_maxTokensCtrl.text.trim().isNotEmpty && maxTokens == null) {
      setState(() => _error = 'Max tokens must be a number.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.reflectMemory(
        query: query,
        bankId: _bank,
        maxTokens: maxTokens,
        includeSources: _includeSources,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SynSpacing.xl,
        SynSpacing.sm,
        SynSpacing.xl,
        SynSpacing.xl,
      ),
      children: [
        SynSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _queryCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Question'),
              ),
              const SizedBox(height: SynSpacing.md),
              Row(
                children: [
                  _BankDropdown(
                    value: _bank,
                    banks: _searchBanks,
                    onChanged: (value) => setState(() => _bank = value),
                  ),
                  const SizedBox(width: SynSpacing.md),
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _maxTokensCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Max tokens',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: SynSpacing.md),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Include sources'),
                        value: _includeSources,
                        onChanged: (value) =>
                            setState(() => _includeSources = value),
                      ),
                    ),
                  ),
                  const SizedBox(width: SynSpacing.md),
                  FilledButton.icon(
                    onPressed: _busy ? null : _reflect,
                    icon: const Icon(Icons.psychology_alt_outlined, size: 16),
                    label: const Text('Reflect'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: SynSpacing.md),
          SynNotice(
            icon: Icons.error_outline,
            title: 'Reflect failed',
            message: _error!,
            color: SynColors.red,
          ),
        ],
        if (_busy) ...[
          const SizedBox(height: SynSpacing.xl),
          const Center(child: CircularProgressIndicator()),
        ],
        if (_result != null) ...[
          const SizedBox(height: SynSpacing.md),
          SynSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Answer', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: SynSpacing.sm),
                SelectableText(_result!.answer),
                const SizedBox(height: SynSpacing.lg),
                Text('Sources', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: SynSpacing.sm),
                _JsonBlock(value: _result!.sources),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RetainTab extends StatefulWidget {
  final SynapseApiClient apiClient;

  const _RetainTab({required this.apiClient});

  @override
  State<_RetainTab> createState() => _RetainTabState();
}

class _RetainTabState extends State<_RetainTab> {
  final _contentCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _metadataCtrl = TextEditingController();
  RetainMemoryResponse? _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _contentCtrl.dispose();
    _tagsCtrl.dispose();
    _metadataCtrl.dispose();
    super.dispose();
  }

  Future<void> _retain() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      setState(() => _error = 'Content is required.');
      return;
    }
    final metadata = _parseJsonMap(_metadataCtrl.text);
    if (_metadataCtrl.text.trim().isNotEmpty && metadata == null) {
      setState(() => _error = 'Metadata must be valid JSON object.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.retainMemory(
        content: content,
        tags: _csv(_tagsCtrl.text),
        metadata: metadata,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear() {
    _contentCtrl.clear();
    _tagsCtrl.clear();
    _metadataCtrl.clear();
    setState(() {
      _result = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SynSpacing.xl,
        SynSpacing.sm,
        SynSpacing.xl,
        SynSpacing.xl,
      ),
      children: [
        SynSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Retain agent memory',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const _FixedBankChip(bank: 'agents'),
                ],
              ),
              const SizedBox(height: SynSpacing.md),
              TextField(
                controller: _contentCtrl,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(labelText: 'Content'),
              ),
              const SizedBox(height: SynSpacing.md),
              TextField(
                controller: _tagsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: 'project, decision, follow-up',
                ),
              ),
              const SizedBox(height: SynSpacing.md),
              TextField(
                controller: _metadataCtrl,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Metadata JSON (optional)',
                  hintText: '{"source":"manual"}',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: SynSpacing.md),
                Text(
                  _error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: SynColors.red),
                ),
              ],
              const SizedBox(height: SynSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _clear,
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear'),
                  ),
                  const SizedBox(width: SynSpacing.sm),
                  FilledButton.icon(
                    onPressed: _busy ? null : _retain,
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    label: const Text('Retain'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: SynSpacing.md),
          SynNotice(
            icon: Icons.check_circle_outline,
            title: 'Stored',
            message:
                'Memory ID: ${_result!.memoryId}\nStored: ${_result!.stored}',
            color: SynColors.green,
          ),
        ],
        const SizedBox(height: SynSpacing.md),
        _ForgetPanel(apiClient: widget.apiClient),
      ],
    );
  }
}

class _ForgetPanel extends StatefulWidget {
  final SynapseApiClient apiClient;

  const _ForgetPanel({required this.apiClient});

  @override
  State<_ForgetPanel> createState() => _ForgetPanelState();
}

class _ForgetPanelState extends State<_ForgetPanel> {
  final _idsCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  Map<String, dynamic>? _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _idsCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _forget() async {
    final ids = _csv(_idsCtrl.text);
    final tags = _csv(_tagsCtrl.text);
    if (ids.isEmpty && tags.isEmpty) {
      setState(() => _error = 'Provide memory IDs or tags to forget.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget agent memories?'),
        content: const Text(
          'This deletes matching memories from the agents bank.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.forgetMemory(
        memoryIds: ids.isEmpty ? null : ids,
        tags: tags.isEmpty ? null : tags,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SynSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Forget agent memories',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const _FixedBankChip(bank: 'agents'),
            ],
          ),
          const SizedBox(height: SynSpacing.md),
          TextField(
            controller: _idsCtrl,
            decoration: const InputDecoration(
              labelText: 'Memory IDs',
              hintText: 'mem_1, mem_2',
            ),
          ),
          const SizedBox(height: SynSpacing.md),
          TextField(
            controller: _tagsCtrl,
            decoration: const InputDecoration(
              labelText: 'Tags',
              hintText: 'obsolete, draft',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: SynSpacing.md),
            Text(
              _error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: SynColors.red),
            ),
          ],
          const SizedBox(height: SynSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _forget,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Forget'),
            ),
          ),
          if (_result != null) ...[
            const SizedBox(height: SynSpacing.md),
            _JsonBlock(value: _result!),
          ],
        ],
      ),
    );
  }
}

class _GraphTab extends StatefulWidget {
  final SynapseApiClient apiClient;

  const _GraphTab({required this.apiClient});

  @override
  State<_GraphTab> createState() => _GraphTabState();
}

class _GraphTabState extends State<_GraphTab> {
  final _queryCtrl = TextEditingController();
  final _entityIdsCtrl = TextEditingController();
  String _searchBank = 'decisions';
  String _neighborsBank = 'decisions';
  int _searchLimit = 10;
  int _maxDepth = 1;
  int _neighborsLimit = 10;
  MemoryGraphSearchResponse? _searchResult;
  MemoryGraphNeighborsResponse? _neighborsResult;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _queryCtrl.dispose();
    _entityIdsCtrl.dispose();
    super.dispose();
  }

  Future<void> _graphSearch() async {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'Graph query is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.graphSearchMemory(
        query: query,
        bankId: _searchBank,
        limit: _searchLimit,
      );
      if (!mounted) return;
      setState(() => _searchResult = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _neighbors() async {
    final ids = _csv(_entityIdsCtrl.text);
    if (ids.isEmpty) {
      setState(() => _error = 'Entity IDs are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.graphNeighborsMemory(
        entityIds: ids,
        bankId: _neighborsBank,
        maxDepth: _maxDepth,
        limit: _neighborsLimit,
      );
      if (!mounted) return;
      setState(() => _neighborsResult = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _useEntity(String entityId) {
    final ids = _csv(_entityIdsCtrl.text);
    if (!ids.contains(entityId)) ids.add(entityId);
    _entityIdsCtrl.text = ids.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SynSpacing.xl,
        SynSpacing.sm,
        SynSpacing.xl,
        SynSpacing.xl,
      ),
      children: [
        SynSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Graph search',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: SynSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Entity query',
                      ),
                      onSubmitted: (_) => _graphSearch(),
                    ),
                  ),
                  const SizedBox(width: SynSpacing.md),
                  _BankDropdown(
                    value: _searchBank,
                    banks: _graphBanks,
                    onChanged: (value) => setState(() => _searchBank = value),
                  ),
                  const SizedBox(width: SynSpacing.md),
                  _LimitDropdown(
                    value: _searchLimit,
                    values: const [5, 10, 20, 50],
                    onChanged: (value) => setState(() => _searchLimit = value),
                  ),
                  const SizedBox(width: SynSpacing.md),
                  FilledButton.icon(
                    onPressed: _busy ? null : _graphSearch,
                    icon: const Icon(Icons.hub_outlined, size: 16),
                    label: const Text('Search'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: SynSpacing.md),
          SynNotice(
            icon: Icons.error_outline,
            title: 'Graph operation failed',
            message: _error!,
            color: SynColors.red,
          ),
        ],
        if (_searchResult != null) ...[
          const SizedBox(height: SynSpacing.md),
          ..._searchResult!.entities.map(
            (entity) => Padding(
              padding: const EdgeInsets.only(bottom: SynSpacing.sm),
              child: SynSurface(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            entity.name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: SynSpacing.xs),
                          Text(
                            '${entity.entityType}  ${entity.entityId}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: SynColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _useEntity(entity.entityId),
                      child: const Text('Use'),
                    ),
                    const SizedBox(width: SynSpacing.sm),
                    IconButton(
                      tooltip: 'Copy entity ID',
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: entity.entityId),
                      ),
                      icon: const Icon(Icons.copy, size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: SynSpacing.md),
        SynSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Graph neighbors',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: SynSpacing.md),
              TextField(
                controller: _entityIdsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Entity IDs',
                  hintText: 'entity_1, entity_2',
                ),
              ),
              const SizedBox(height: SynSpacing.md),
              Row(
                children: [
                  _BankDropdown(
                    value: _neighborsBank,
                    banks: _graphBanks,
                    onChanged: (value) =>
                        setState(() => _neighborsBank = value),
                  ),
                  const SizedBox(width: SynSpacing.md),
                  _LimitDropdown(
                    label: 'Depth',
                    value: _maxDepth,
                    values: const [1, 2, 3, 4, 5],
                    onChanged: (value) => setState(() => _maxDepth = value),
                  ),
                  const SizedBox(width: SynSpacing.md),
                  _LimitDropdown(
                    value: _neighborsLimit,
                    values: const [5, 10, 20, 50],
                    onChanged: (value) =>
                        setState(() => _neighborsLimit = value),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _busy ? null : _neighbors,
                    icon: const Icon(Icons.travel_explore, size: 16),
                    label: const Text('Find neighbors'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_neighborsResult != null) ...[
          const SizedBox(height: SynSpacing.md),
          ..._neighborsResult!.hits.map(
            (hit) => Padding(
              padding: const EdgeInsets.only(bottom: SynSpacing.sm),
              child: _MemoryHitTile(hit: hit),
            ),
          ),
        ],
      ],
    );
  }
}

class _CompileTab extends StatefulWidget {
  final SynapseApiClient apiClient;

  const _CompileTab({required this.apiClient});

  @override
  State<_CompileTab> createState() => _CompileTabState();
}

class _CompileTabState extends State<_CompileTab> {
  final _scopeCtrl = TextEditingController();
  String _bank = 'decisions';
  Map<String, dynamic>? _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _scopeCtrl.dispose();
    super.dispose();
  }

  Future<void> _compile() async {
    final scope = _parseJsonMap(_scopeCtrl.text);
    if (_scopeCtrl.text.trim().isNotEmpty && scope == null) {
      setState(() => _error = 'Scope must be valid JSON object.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.apiClient.compileMemory(
        bankId: _bank,
        scope: scope,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SynSpacing.xl,
        SynSpacing.sm,
        SynSpacing.xl,
        SynSpacing.xl,
      ),
      children: [
        SynSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _BankDropdown(
                    value: _bank,
                    banks: _compileBanks,
                    onChanged: (value) => setState(() => _bank = value),
                  ),
                  const SizedBox(width: SynSpacing.md),
                  FilledButton.icon(
                    onPressed: _busy ? null : _compile,
                    icon: const Icon(
                      Icons.auto_awesome_motion_outlined,
                      size: 16,
                    ),
                    label: const Text('Compile'),
                  ),
                ],
              ),
              const SizedBox(height: SynSpacing.md),
              TextField(
                controller: _scopeCtrl,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Scope JSON (optional)',
                  hintText: '{"topic":"roadmap"}',
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: SynSpacing.md),
          SynNotice(
            icon: Icons.error_outline,
            title: 'Compile failed',
            message: _error!,
            color: SynColors.red,
          ),
        ],
        if (_busy) ...[
          const SizedBox(height: SynSpacing.xl),
          const Center(child: CircularProgressIndicator()),
        ],
        if (_result != null) ...[
          const SizedBox(height: SynSpacing.md),
          SynSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compile response',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: SynSpacing.sm),
                _JsonBlock(value: _result!),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MemoryHitTile extends StatelessWidget {
  final MemoryHit hit;

  const _MemoryHitTile({required this.hit});

  @override
  Widget build(BuildContext context) {
    final score = hit.score.clamp(0, 1).toDouble();
    final pct = (score * 100).round();
    final color = score >= 0.7
        ? SynColors.green
        : score >= 0.4
        ? SynColors.amber
        : SynColors.textFaint;

    return SynSurface(
      padding: const EdgeInsets.all(SynSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                hit.bankId,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: SynColors.textFaint),
              ),
              const Spacer(),
              Text(
                '$pct% match',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: SynSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: score,
              minHeight: 3,
              backgroundColor: SynColors.surfaceRaised,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: SynSpacing.sm),
          SelectableText(hit.content),
          if (hit.tags.isNotEmpty) ...[
            const SizedBox(height: SynSpacing.sm),
            Wrap(
              spacing: SynSpacing.xs,
              runSpacing: SynSpacing.xs,
              children: [
                for (final tag in hit.tags)
                  _SmallChip(label: tag, color: SynColors.primary),
              ],
            ),
          ],
          if (hit.metadata.isNotEmpty) ...[
            const SizedBox(height: SynSpacing.sm),
            Text(
              'Metadata',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: SynColors.textMuted),
            ),
            const SizedBox(height: SynSpacing.xs),
            _JsonBlock(value: hit.metadata, maxHeight: 120),
          ],
        ],
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  final Object? value;
  final double maxHeight;

  const _JsonBlock({required this.value, this.maxHeight = 260});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.all(SynSpacing.md),
      decoration: BoxDecoration(
        color: SynColors.surfaceMuted,
        borderRadius: BorderRadius.circular(SynRadii.md),
        border: Border.all(color: SynColors.border),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          _prettyJson(value),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}

class _BankDropdown extends StatelessWidget {
  final String value;
  final List<String> banks;
  final ValueChanged<String> onChanged;

  const _BankDropdown({
    required this.value,
    required this.banks,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: const InputDecoration(labelText: 'Bank'),
        items: [
          for (final bank in banks)
            DropdownMenuItem(value: bank, child: Text(_titleCase(bank))),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _LimitDropdown extends StatelessWidget {
  final String label;
  final int value;
  final List<int> values;
  final ValueChanged<int> onChanged;

  const _LimitDropdown({
    this.label = 'Limit',
    required this.value,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final item in values)
            DropdownMenuItem(value: item, child: Text(item.toString())),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _FixedBankChip extends StatelessWidget {
  final String bank;

  const _FixedBankChip({required this.bank});

  @override
  Widget build(BuildContext context) {
    return _SmallChip(label: 'Bank: $bank', color: SynColors.textMuted);
  }
}

class _SmallChip extends StatelessWidget {
  final String label;
  final Color color;

  const _SmallChip({required this.label, required this.color});

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
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

Map<String, dynamic>? _parseJsonMap(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    return null;
  }
  return null;
}

int? _parseOptionalInt(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return int.tryParse(trimmed);
}

List<String> _csv(String text) {
  return text
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: true);
}

String _prettyJson(Object? value) {
  return const JsonEncoder.withIndent('  ').convert(value ?? {});
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1).replaceAll('_', ' ');
}
