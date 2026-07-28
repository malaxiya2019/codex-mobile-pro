import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/app_locale.dart';
import '../../../core/i18n/strings.dart';

/// 语言设置页面
class LocaleSettingsPage extends ConsumerWidget {
  const LocaleSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLang = ref.watch(localeProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = Strings.get(currentLang);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.settings),
        backgroundColor: colorScheme.surfaceContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('语言 / Language', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  ...AppLanguage.values.map((lang) {
                    final selected = lang == currentLang;
                    return ListTile(
                      leading: Icon(
                        selected ? Icons.check_circle : Icons.language,
                        color: selected ? colorScheme.primary : null,
                      ),
                      title: Text(lang.displayName),
                      subtitle: Text(
                        lang == AppLanguage.zhCN ? '中文界面' : 'English UI',
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: selected
                          ? Icon(Icons.check, color: colorScheme.primary)
                          : null,
                      onTap: () {
                        ref.read(localeProvider.notifier).setLocale(lang);
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('预览 / Preview', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Text(s.appName, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '${s.navHome} · ${s.navDeploy} · ${s.navTermux} · ${s.navAi}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${s.ok} · ${s.cancel} · ${s.retry} · ${s.save}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
