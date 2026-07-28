import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'workspace_model.dart';

/// SharedPreferences 键
const _kWorkspacesKey = 'workspaces';
const _kCurrentWorkspaceIdKey = 'current_workspace_id';

/// 工作区状态
class WorkspaceState {
  final List<Workspace> workspaces;
  final String? currentWorkspaceId;
  final bool isLoading;

  const WorkspaceState({
    this.workspaces = const [],
    this.currentWorkspaceId,
    this.isLoading = false,
  });

  /// 当前工作区
  Workspace? get currentWorkspace {
    if (currentWorkspaceId == null) return null;
    try {
      return workspaces.firstWhere((w) => w.id == currentWorkspaceId);
    } catch (_) {
      return null;
    }
  }

  WorkspaceState copyWith({
    List<Workspace>? workspaces,
    String? currentWorkspaceId,
    bool? isLoading,
    bool clearCurrent = false,
  }) {
    return WorkspaceState(
      workspaces: workspaces ?? this.workspaces,
      currentWorkspaceId: clearCurrent
          ? null
          : (currentWorkspaceId ?? this.currentWorkspaceId),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 工作区 Provider
final workspaceProvider =
    StateNotifierProvider<WorkspaceNotifier, WorkspaceState>((ref) {
      return WorkspaceNotifier();
    });

class WorkspaceNotifier extends StateNotifier<WorkspaceState> {
  WorkspaceNotifier() : super(const WorkspaceState()) {
    _load();
  }

  /// 从 SharedPreferences 加载
  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载工作区列表
      final workspacesJson = prefs.getString(_kWorkspacesKey);
      final List<Workspace> workspaces = [];
      if (workspacesJson != null) {
        final list = jsonDecode(workspacesJson) as List<dynamic>;
        for (final item in list) {
          try {
            workspaces.add(Workspace.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            // 跳过损坏数据
          }
        }
      }

      // 加载当前工作区 ID
      final currentId = prefs.getString(_kCurrentWorkspaceIdKey);

      // 如果当前 ID 不在列表中，清空
      String? validCurrentId;
      if (currentId != null && workspaces.any((w) => w.id == currentId)) {
        validCurrentId = currentId;
      }

      state = WorkspaceState(
        workspaces: workspaces,
        currentWorkspaceId: validCurrentId,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// 持久化保存
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = state.workspaces.map((w) => w.toJson()).toList();
      await prefs.setString(_kWorkspacesKey, jsonEncode(jsonList));
      if (state.currentWorkspaceId != null) {
        await prefs.setString(
          _kCurrentWorkspaceIdKey,
          state.currentWorkspaceId!,
        );
      } else {
        await prefs.remove(_kCurrentWorkspaceIdKey);
      }
    } catch (_) {}
  }

  /// 创建工作区
  Future<Workspace> create({
    required String name,
    required WorkspaceTemplate template,
  }) async {
    final now = DateTime.now();
    final workspace = Workspace(
      id: const Uuid().v4(),
      name: name,
      template: template,
      createdAt: now,
      updatedAt: now,
    );

    state = state.copyWith(workspaces: [...state.workspaces, workspace]);
    await _save();
    return workspace;
  }

  /// 删除工作区
  Future<void> delete(String id) async {
    final ws = state.workspaces.where((w) => w.id != id).toList();
    final shouldClear = state.currentWorkspaceId == id;
    state = state.copyWith(
      workspaces: ws,
      clearCurrent: shouldClear,
    );
    await _save();
  }

  /// 更新工作区
  Future<void> update(Workspace workspace) async {
    final ws = state.workspaces.map((w) {
      return w.id == workspace.id ? workspace : w;
    }).toList();

    state = state.copyWith(workspaces: ws);
    await _save();
  }

  /// 切换当前工作区
  Future<void> switchWorkspace(String id) async {
    if (state.workspaces.any((w) => w.id == id)) {
      state = state.copyWith(currentWorkspaceId: id);
      await _save();
    }
  }

  /// 取消选择工作区
  Future<void> clearCurrentWorkspace() async {
    state = state.copyWith(clearCurrent: true);
    await _save();
  }

  /// 添加项目到工作区
  Future<void> addProject(String workspaceId, ProjectRef project) async {
    final ws = state.workspaces.map((w) {
      if (w.id != workspaceId) return w;
      return w.copyWith(
        projects: [...w.projects, project],
        updatedAt: DateTime.now(),
      );
    }).toList();

    state = state.copyWith(workspaces: ws);
    await _save();
  }

  /// 从工作区移除项目
  Future<void> removeProject(String workspaceId, String projectId) async {
    final ws = state.workspaces.map((w) {
      if (w.id != workspaceId) return w;
      return w.copyWith(
        projects: w.projects.where((p) => p.id != projectId).toList(),
        updatedAt: DateTime.now(),
      );
    }).toList();

    state = state.copyWith(workspaces: ws);
    await _save();
  }

  /// 获取工作区数量
  int get count => state.workspaces.length;
}
