import 'dart:io';
import '../../models/project_template.dart';
import '../project_generator.dart';

/// Flutter 项目模板生成器
class FlutterTemplateGenerator extends TemplateGenerator {
  @override
  ProjectTemplateType get type => ProjectTemplateType.flutter;

  @override
  ProjectTemplate get template => ProjectTemplate(
    id: 'flutter-default',
    type: ProjectTemplateType.flutter,
    name: 'Flutter 默认模板',
    description: '标准的 Flutter 项目结构，包含基础 Material App 配置',
    icon: '📱',
    version: const TemplateVersion(
      version: '1.0.0',
      releaseDate: DateTime(2026, 7, 28),
    ),
    requiredTools: ['flutter', 'dart'],
    generatedFiles: [
      'lib/main.dart',
      'pubspec.yaml',
      'analysis_options.yaml',
      'test/widget_test.dart',
    ],
    defaultConfig: {'org': 'com.example', 'platforms': 'android,ios'},
  );

  @override
  Future<ProjectCreateResult> generate(ProjectCreateConfig config) async {
    try {
      // 1. 创建项目目录
      await createProjectDir(config.path, config.name);

      final projectPath = '${config.path}/${config.name}';
      final org = config.options['org'] ?? 'com.example';

      // 2. 执行 flutter create
      final result = await Process.run('flutter', [
        'create',
        '--org',
        org,
        projectPath,
      ], runInShell: true);

      if (result.exitCode != 0) {
        // flutter create 失败，创建基础文件结构
        await _createFallbackStructure(projectPath, config.name);
      }

      return ProjectCreateResult(
        success: true,
        projectPath: projectPath,
        exitCode: result.exitCode,
        stdout: result.stdout as String?,
        stderr: result.stderr as String?,
      );
    } catch (e) {
      return ProjectCreateResult(
        success: false,
        projectPath: '${config.path}/${config.name}',
        errorMessage: e.toString(),
      );
    }
  }

  /// 当 flutter create 不可用时创建基础结构
  Future<void> _createFallbackStructure(String projectPath, String name) async {
    Directory(projectPath); // dir

    // 基础目录
    await Directory('$projectPath/lib').create(recursive: true);
    await Directory('$projectPath/test').create(recursive: true);
    await Directory(
      '$projectPath/android/app/src/main',
    ).create(recursive: true);
    await Directory('$projectPath/ios').create(recursive: true);
    await Directory('$projectPath/assets').create(recursive: true);

    // pubspec.yaml
    await File('$projectPath/pubspec.yaml').writeAsString('''
name: ${name.toLowerCase().replaceAll(' ', '_')}
description: "A new Flutter project."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
''');

    // lib/main.dart
    await File('$projectPath/lib/main.dart').writeAsString('''
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$name',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('Hello, World!'),
        ),
      ),
    );
  }
}
''');

    // analysis_options.yaml
    await File('$projectPath/analysis_options.yaml').writeAsString('''
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    prefer_const_constructors: true
    prefer_const_declarations: true
    avoid_print: false
''');
  }

  @override
  Future<List<String>> checkRequirements() async {
    final missing = <String>[];

    try {
      final result = await Process.run('which', ['flutter'], runInShell: true);
      if (result.exitCode != 0) missing.add('flutter');
    } catch (_) {
      missing.add('flutter');
    }

    try {
      final result = await Process.run('which', ['dart'], runInShell: true);
      if (result.exitCode != 0) missing.add('dart');
    } catch (_) {
      missing.add('dart');
    }

    return missing;
  }
}
