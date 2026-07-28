import 'dart:io';
import '../../models/project_template.dart';
import '../project_generator.dart';

/// Python 项目模板生成器
class PythonTemplateGenerator extends TemplateGenerator {
  @override
  ProjectTemplateType get type => ProjectTemplateType.python;

  @override
  ProjectTemplate get template => ProjectTemplate(
    id: 'python-default',
    type: ProjectTemplateType.python,
    name: 'Python 默认模板',
    description: '标准的 Python 项目结构，包含 venv 和 requirements.txt',
    icon: '🐍',
    version: TemplateVersion(
      version: '1.0.0',
      releaseDate: DateTime(2026, 7, 28),
    ),
    requiredTools: ['python3'],
    generatedFiles: ['main.py', 'requirements.txt', '.gitignore', 'README.md'],
    defaultConfig: {'python_version': '3.10'},
  );

  @override
  Future<ProjectCreateResult> generate(ProjectCreateConfig config) async {
    try {
      await createProjectDir(config.path, config.name);
      final projectPath = '${config.path}/${config.name}';

      // 创建项目目录结构
      await _createProjectStructure(projectPath, config.name);

      // 尝试创建 venv
      final venvResult = await _tryCreateVenv(projectPath);

      return ProjectCreateResult(
        success: true,
        projectPath: projectPath,
        exitCode: venvResult ? 0 : 1,
      );
    } catch (e) {
      return ProjectCreateResult(
        success: false,
        projectPath: '${config.path}/${config.name}',
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _createProjectStructure(String projectPath, String name) async {
    final packageName = name
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_');

    // 源代码目录
    await Directory('$projectPath/$packageName').create(recursive: true);
    await Directory('$projectPath/tests').create(recursive: true);

    // __init__.py
    await File('$projectPath/$packageName/__init__.py').writeAsString('''
"""$name - A Python project."""

__version__ = "0.1.0"
''');

    // main.py
    await File('$projectPath/main.py').writeAsString('''"""
$name
"""


def main():
    print("Hello, World!")


if __name__ == "__main__":
    main()
''');

    // tests/__init__.py
    await File('$projectPath/tests/__init__.py').writeAsString('');

    // requirements.txt
    await File(
      '$projectPath/requirements.txt',
    ).writeAsString('# 项目依赖\n# pip install -r requirements.txt\n');

    // .gitignore
    await File('$projectPath/.gitignore').writeAsString('''
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
venv/
.venv/
*.egg-info/
dist/
build/
.eggs/
*.egg
''');

    // README.md
    await File('$projectPath/README.md').writeAsString('''
# $name

A Python project.

## 快速开始

```bash
# 创建虚拟环境
python3 -m venv venv
source venv/bin/activate

# 安装依赖
pip install -r requirements.txt

# 运行
python main.py
```
''');
  }

  Future<bool> _tryCreateVenv(String projectPath) async {
    try {
      final result = await Process.run('python3', [
        '-m',
        'venv',
        '$projectPath/venv',
      ], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> checkRequirements() async {
    final missing = <String>[];

    try {
      final result = await Process.run('which', ['python3'], runInShell: true);
      if (result.exitCode != 0) {
        // 尝试 python
        final result2 = await Process.run('which', [
          'python',
        ], runInShell: true);
        if (result2.exitCode != 0) missing.add('python3');
      }
    } catch (_) {
      missing.add('python3');
    }

    return missing;
  }
}
