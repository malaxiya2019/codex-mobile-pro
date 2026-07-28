import 'dart:io';
import '../../models/project_template.dart';
import '../project_generator.dart';

/// Rust 项目模板生成器
class RustTemplateGenerator extends TemplateGenerator {
  @override
  ProjectTemplateType get type => ProjectTemplateType.rust;

  @override
  ProjectTemplate get template => ProjectTemplate(
    id: 'rust-default',
    type: ProjectTemplateType.rust,
    name: 'Rust 默认模板',
    description: '标准的 Rust 项目结构，使用 cargo 初始化',
    icon: '🦀',
    version: const TemplateVersion(
      version: '1.0.0',
      releaseDate: DateTime(2026, 7, 28),
    ),
    requiredTools: ['cargo', 'rustc'],
    generatedFiles: ['Cargo.toml', 'src/main.rs', '.gitignore'],
    defaultConfig: {'edition': '2021'},
  );

  @override
  Future<ProjectCreateResult> generate(ProjectCreateConfig config) async {
    try {
      await createProjectDir(config.path, config.name);
      final projectPath = '${config.path}/${config.name}';

      // 尝试使用 cargo init
      final result = await Process.run('cargo', [
        'init',
        projectPath,
        '--name',
        config.name,
      ], runInShell: true);

      if (result.exitCode != 0) {
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

  Future<void> _createFallbackStructure(String projectPath, String name) async {
    await Directory('$projectPath/src').create(recursive: true);

    await File('$projectPath/Cargo.toml').writeAsString('''
[package]
name = "${name.toLowerCase().replaceAll(' ', '_')}"
version = "0.1.0"
edition = "2021"
description = "A Rust project"

[dependencies]
''');

    await File('$projectPath/src/main.rs').writeAsString('''
fn main() {
    println!("Hello, world!");
}
''');

    await File('$projectPath/.gitignore').writeAsString('''
/target
**/*.rs.bk
Cargo.lock
''');
  }

  @override
  Future<List<String>> checkRequirements() async {
    final missing = <String>[];

    try {
      final result = await Process.run('which', ['cargo'], runInShell: true);
      if (result.exitCode != 0) missing.add('cargo');
    } catch (_) {
      missing.add('cargo');
    }

    try {
      final result = await Process.run('which', ['rustc'], runInShell: true);
      if (result.exitCode != 0) missing.add('rustc');
    } catch (_) {
      missing.add('rustc');
    }

    return missing;
  }
}
