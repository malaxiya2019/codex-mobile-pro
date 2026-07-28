import 'dart:io';
import '../models/project_template.dart';

/// 模板生成器抽象基类
///
/// 所有语言模板生成器继承此类，模板与生成逻辑分离。
/// 新增语言只需实现 [generate] 方法并注册到 [ProjectGeneratorService]。
abstract class TemplateGenerator {
  /// 模板类型
  ProjectTemplateType get type;

  /// 生成项目
  ///
  /// [config] 项目创建配置
  /// 返回 [ProjectCreateResult]
  Future<ProjectCreateResult> generate(ProjectCreateConfig config);

  /// 获取模板信息
  ProjectTemplate get template;

  /// 验证环境是否满足要求
  Future<List<String>> checkRequirements();

  /// 创建项目目录
  Future<Directory> createProjectDir(String path, String name) async {
    final projectDir = Directory('$path/$name');
    if (await projectDir.exists()) {
      throw Exception('项目目录已存在: $projectDir');
    }
    await projectDir.create(recursive: true);
    return projectDir;
  }
}

/// 项目生成器服务
///
/// 统一管理所有模板生成器，提供项目创建入口。
class ProjectGeneratorService {
  final List<TemplateGenerator> _generators = [];

  /// 注册模板生成器
  void register(TemplateGenerator generator) {
    _generators.removeWhere((g) => g.type == generator.type);
    _generators.add(generator);
  }

  /// 获取所有支持的模板
  List<ProjectTemplate> get availableTemplates =>
      _generators.map((g) => g.template).toList();

  /// 生成项目
  Future<ProjectCreateResult> createProject(ProjectCreateConfig config) async {
    final generator = _generators
        .where((g) => g.type == config.type)
        .firstOrNull;
    if (generator == null) {
      return ProjectCreateResult(
        success: false,
        projectPath: config.path,
        errorMessage: '不支持的模板类型: ${config.type.name}',
      );
    }
    return generator.generate(config);
  }

  /// 获取指定类型的模板信息
  ProjectTemplate? getTemplate(ProjectTemplateType type) {
    return _generators.where((g) => g.type == type).firstOrNull?.template;
  }

  /// 检查环境需求
  Future<Map<ProjectTemplateType, List<String>>> checkAllRequirements() async {
    final result = <ProjectTemplateType, List<String>>{};
    for (final g in _generators) {
      result[g.type] = await g.checkRequirements();
    }
    return result;
  }
}
