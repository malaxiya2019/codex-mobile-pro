import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';
import '../workspace_model.dart';
import '../workspace_provider.dart';

/// 工作区创建对话框
class WorkspaceCreateDialog extends ConsumerStatefulWidget {
  const WorkspaceCreateDialog({super.key});

  /// 显示对话框
  static Future<Workspace?> show(BuildContext context) {
    return showDialog<Workspace>(
      context: context,
      builder: (ctx) => const WorkspaceCreateDialog(),
    );
  }

  @override
  ConsumerState<WorkspaceCreateDialog> createState() =>
      _WorkspaceCreateDialogState();
}

class _WorkspaceCreateDialogState extends ConsumerState<WorkspaceCreateDialog> {
  final _nameController = TextEditingController();
  WorkspaceTemplate _selectedTemplate = WorkspaceTemplate.flutter;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = ref.watch(localeProvider);
    final s = Strings.get(locale);

    return AlertDialog(
      title: Text(s.workspaceCreateTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 工作区名称
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: s.workspaceNameHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.workspace_premium),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 20),

            // 模板选择
            Text(
              s.workspaceTemplateLabel,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            // 模板网格
            ...WorkspaceTemplate.values.map(
              (tpl) => _TemplateOption(
                template: tpl,
                isSelected: _selectedTemplate == tpl,
                onTap: () => setState(() => _selectedTemplate = tpl),
                locale: locale,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _isCreating ? null : _create,
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(s.confirm),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);

    try {
      final workspace = await ref
          .read(workspaceProvider.notifier)
          .create(name: name, template: _selectedTemplate);

      if (mounted) {
        Navigator.of(context).pop(workspace);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${Strings.get(ref.read(localeProvider)).error}: $e'),
          ),
        );
      }
    }
  }
}

/// 模板选择项
class _TemplateOption extends StatelessWidget {
  final WorkspaceTemplate template;
  final bool isSelected;
  final VoidCallback onTap;
  final AppLanguage locale;

  const _TemplateOption({
    required this.template,
    required this.isSelected,
    required this.onTap,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
            color: isSelected
                ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text(template.icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      template.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: colorScheme.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
