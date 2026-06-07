import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/client.dart';
import '../../core/api/models.dart';
import '../../ui/synapse_components.dart';
import '../../ui/synapse_shell.dart';
import '../../ui/synapse_tokens.dart';

class CreateCouncilScreen extends StatefulWidget {
  final SynapseApiClient client;

  const CreateCouncilScreen({super.key, required this.client});

  @override
  State<CreateCouncilScreen> createState() => _CreateCouncilScreenState();
}

class _CreateCouncilScreenState extends State<CreateCouncilScreen> {
  final _questionController = TextEditingController();
  List<Template> _templates = [];
  Template? _selectedTemplate;
  String _councilType = 'llm';
  CouncilMode _mode = CouncilMode.standard;
  bool _loading = false;
  bool _loadingTemplates = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    try {
      final templates = await widget.client.listTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _loadingTemplates = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTemplates = false);
    }
  }

  Future<void> _submit() async {
    final question = _questionController.text.trim();
    if (question.isEmpty) {
      setState(() => _error = 'Question is required.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await widget.client.createCouncil(
        question: question,
        templateId: _selectedTemplate?.id,
        councilType: _councilType,
        mode: _mode,
      );
      if (!mounted) return;
      context.go(
        '/councils/${response.sessionId}/chat',
        extra: {'threadId': response.threadId, 'status': response.status},
      );
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

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SynapseWorkspaceFrame(
      selected: SynapseNavItem.councils,
      title: 'New council',
      onBack: () => context.go('/councils'),
      actions: [
        FilledButton.icon(
          onPressed: _loading ? null : _submit,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Start'),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 880;
          final form = _FormPanel(
            questionController: _questionController,
            templates: _templates,
            selectedTemplate: _selectedTemplate,
            loadingTemplates: _loadingTemplates,
            councilType: _councilType,
            mode: _mode,
            error: _error,
            onTemplateChanged: (value) =>
                setState(() => _selectedTemplate = value),
            onCouncilTypeChanged: (value) =>
                setState(() => _councilType = value),
            onModeChanged: (value) => setState(() => _mode = value),
            onSubmit: _submit,
            loading: _loading,
          );
          final summary = _SummaryPanel(
            template: _selectedTemplate,
            councilType: _councilType,
            mode: _mode,
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(SynSpacing.xl),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      form,
                      const SizedBox(height: SynSpacing.lg),
                      summary,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: form),
                      const SizedBox(width: SynSpacing.lg),
                      Expanded(flex: 2, child: summary),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _FormPanel extends StatelessWidget {
  final TextEditingController questionController;
  final List<Template> templates;
  final Template? selectedTemplate;
  final bool loadingTemplates;
  final String councilType;
  final CouncilMode mode;
  final String? error;
  final ValueChanged<Template?> onTemplateChanged;
  final ValueChanged<String> onCouncilTypeChanged;
  final ValueChanged<CouncilMode> onModeChanged;
  final VoidCallback onSubmit;
  final bool loading;

  const _FormPanel({
    required this.questionController,
    required this.templates,
    required this.selectedTemplate,
    required this.loadingTemplates,
    required this.councilType,
    required this.mode,
    required this.error,
    required this.onTemplateChanged,
    required this.onCouncilTypeChanged,
    required this.onModeChanged,
    required this.onSubmit,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return SynSurface(
      color: SynColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Question', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: SynSpacing.md),
          TextField(
            controller: questionController,
            autofocus: true,
            maxLines: 7,
            minLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: 'What decision should the council deliberate on?',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: SynSpacing.lg),
          if (loadingTemplates)
            const SizedBox(
              height: 42,
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            DropdownButtonFormField<Template?>(
              initialValue: selectedTemplate,
              decoration: const InputDecoration(
                labelText: 'Template',
                prefixIcon: Icon(Icons.library_books_outlined),
              ),
              items: [
                const DropdownMenuItem<Template?>(
                  value: null,
                  child: Text('None'),
                ),
                ...templates.map(
                  (template) => DropdownMenuItem<Template?>(
                    value: template,
                    child: Text(template.name),
                  ),
                ),
              ],
              onChanged: onTemplateChanged,
            ),
          const SizedBox(height: SynSpacing.lg),
          const _SectionLabel(label: 'Council type'),
          const SizedBox(height: SynSpacing.sm),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'llm',
                icon: Icon(Icons.auto_awesome, size: 16),
                label: Text('LLM'),
              ),
              ButtonSegment(
                value: 'async',
                icon: Icon(Icons.groups_2_outlined, size: 16),
                label: Text('Async'),
              ),
            ],
            selected: {councilType},
            onSelectionChanged: (selection) =>
                onCouncilTypeChanged(selection.first),
          ),
          const SizedBox(height: SynSpacing.lg),
          const _SectionLabel(label: 'Mode'),
          const SizedBox(height: SynSpacing.sm),
          SegmentedButton<CouncilMode>(
            segments: const [
              ButtonSegment(
                value: CouncilMode.standard,
                icon: Icon(Icons.route_outlined, size: 16),
                label: Text('Standard'),
              ),
              ButtonSegment(
                value: CouncilMode.redTeam,
                icon: Icon(Icons.gpp_maybe_outlined, size: 16),
                label: Text('Red team'),
              ),
              ButtonSegment(
                value: CouncilMode.deliberation,
                icon: Icon(Icons.sync_alt_outlined, size: 16),
                label: Text('Deliberation'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (selection) => onModeChanged(selection.first),
          ),
          if (error != null) ...[
            const SizedBox(height: SynSpacing.lg),
            SynNotice(
              icon: Icons.error_outline,
              title: 'Create failed',
              message: error!,
              color: SynColors.red,
            ),
          ],
          const SizedBox(height: SynSpacing.xl),
          FilledButton.icon(
            onPressed: loading ? null : onSubmit,
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Start council'),
          ),
        ],
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  final Template? template;
  final String councilType;
  final CouncilMode mode;

  const _SummaryPanel({
    required this.template,
    required this.councilType,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SynSurface(
          color: SynColors.surfaceMuted,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Run profile',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: SynSpacing.lg),
              SynMetaRow(
                label: 'Type',
                value: councilType == 'llm' ? 'LLM council' : 'Async council',
              ),
              const SizedBox(height: SynSpacing.sm),
              SynMetaRow(label: 'Mode', value: mode.label),
              const SizedBox(height: SynSpacing.sm),
              SynMetaRow(label: 'Template', value: template?.name ?? 'None'),
              if (template != null) ...[
                const SizedBox(height: SynSpacing.lg),
                Text(
                  template!.description,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: SynColors.textMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: SynSpacing.lg),
        const SynNotice(
          icon: Icons.key_outlined,
          title: 'LLM credentials required',
          message:
              'If the backend has no provider key, councils will be created but fail during execution.',
          color: SynColors.amber,
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(color: SynColors.textMuted),
    );
  }
}
