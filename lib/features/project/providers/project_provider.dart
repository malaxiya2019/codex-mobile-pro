import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project_template.dart';
import '../services/project_generator.dart';
import '../services/templates/flutter_template_generator.dart';
import '../services/templates/rust_template_generator.dart';
import '../services/templates/python_template_generator.dart';

/// 项目创建状态
enum ProjectCreateState { idle, creating, success, error }

/// 项目状态
class ProjectState {
  final ProjectCreateState createState;
  final List<ProjectInfo> projects;
  final ProjectCreateResult? lastResult;
  final String? errorMessage;
  final bool isLoading;

  const ProjectState({
    this.createState = ProjectCreateState.idle,
    this.projects = const [],
    this.lastResult,
    this.errorMessage,
    this.isLoading = false,
  });

  ProjectState copyWith({
    ProjectCreateState? createState,
    List<ProjectInfo>? projects,
    ProjectCreateResult? lastResult,
    String? errorMessage,
    bool? isLoading,
    bool clearResult = false,
  }) {
    return ProjectState(
      createState: createState ?? this.createState,
      projects: projects ?? this.projects,
      lastResult: clearResult ? null : (lastResult ?? this.lastResult),
      errorMessage: clearResult ? null : (errorMessage ?? this.errorMessage),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 项目 Provider
final projectProvider = StateNotifierProvider<ProjectNotifier, ProjectState>((
  ref,
) {
  return ProjectNotifier();
});

class ProjectNotifier extends StateNotifier<ProjectState> {
  final ProjectGeneratorService _generatorService;

  ProjectNotifier()
    : _generatorService = ProjectGeneratorService(),
      super(const ProjectState()) {
    _registerGenerators();
    _loadProjects();
  }

  void _registerGenerators() {
    _generatorService.register(FlutterTemplateGenerator());
    _generatorService.register(RustTemplateGenerator());
    _generatorService.register(PythonTemplateGenerator());
  }

  /// 获取可用模板列表
  List<ProjectTemplate> get availableTemplates =>
      _generatorService.availableTemplates;

  /// 加载已创建的项目
  Future<void> _loadProjects() async {
    state = state.copyWith(isLoading: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('projects');
      if (jsonStr != null) {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        final projects = list
            .map((e) => ProjectInfo.fromJson(e as Map<String, dynamic>))
            .toList();
        state = state.copyWith(projects: projects, isLoading: false);
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// 保存项目列表
  Future<void> _saveProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(
        state.projects.map((p) => p.toJson()).toList(),
      );
      await prefs.setString('projects', jsonStr);
    } catch (_) {}
  }

  /// 创建项目
  Future<ProjectCreateResult> createProject(ProjectCreateConfig config) async {
    state = state.copyWith(createState: ProjectCreateState.creating);

    final result = await _generatorService.createProject(config);

    if (result.success) {
      final projectInfo = ProjectInfo(
        name: config.name,
        path: result.projectPath,
        type: config.type,
        createdAt: DateTime.now(),
        initialized: true,
      );
      state = state.copyWith(
        createState: ProjectCreateState.success,
        projects: [...state.projects, projectInfo],
        lastResult: result,
      );
      await _saveProjects();
    } else {
      state = state.copyWith(
        createState: ProjectCreateState.error,
        errorMessage: result.errorMessage,
        lastResult: result,
      );
    }

    return result;
  }

  /// 重置创建状态
  void resetCreateState() {
    state = state.copyWith(
      createState: ProjectCreateState.idle,
      clearResult: true,
    );
  }

  /// 删除项目记录
  Future<void> removeProject(String path) async {
    state = state.copyWith(
      projects: state.projects.where((p) => p.path != path).toList(),
    );
    await _saveProjects();
  }

  /// 获取模板信息
  ProjectTemplate? getTemplate(ProjectTemplateType type) {
    return _generatorService.getTemplate(type);
  }
}
