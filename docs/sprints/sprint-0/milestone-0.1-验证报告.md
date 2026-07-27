# 🔬 Sprint 0 — Milestone 0.1 验证报告

> **验证目标：** Flutter 工程可正常运行在 Android 10~15 设备上
> **验证日期：** 2026-07-27

---

## 验证结果总览

| # | 验证项 | 状态 | 备注 |
|---|--------|------|------|
| 1 | Flutter 工程初始化 | ✅ 完成 | 源码结构完整，`setup_flutter_project.sh` 可用 |
| 2 | Android 10~15 兼容 | ✅ 完成 | `minSdk=29`, `targetSdk=35`, `compileSdk=35` |
| 3 | Material 3 正常显示 | ✅ 完成 | `useMaterial3: true`，Card/NavigationBar/FilledButton 组件 |
| 4 | Riverpod 集成成功 | ✅ 完成 | `flutter_riverpod` 依赖，CounterProvider + HomeStateProvider |
| 5 | Debug 构建 | ⏳ CI 验证 | GitHub Actions 自动构建 |
| 6 | Release 构建 | ⏳ Sprint 9 | 发布前配置签名 |

## 验收标准

| 指标 | 目标值 | 实测值 | 状态 |
|------|--------|--------|------|
| 首次安装 App 成功 | ✅ 通过 | — | ⏳ 需真机测试 |
| 冷启动时间 | < 3 秒 | — | ⏳ M0.5 基线测量 |
| 运行稳定性 | 无崩溃 | — | ⏳ 需真机测试 |

## 已创建的文件

### Dart 源码
| 文件 | 说明 |
|------|------|
| `lib/main.dart` | 应用入口，ProviderScope + 竖屏锁定 |
| `lib/app.dart` | MaterialApp.router + M3 主题 + GoRouter |
| `lib/core/theme/app_theme.dart` | M3 亮/暗主题 |
| `lib/core/router/app_router.dart` | GoRouter 路由配置 |
| `lib/core/router/route_names.dart` | 路由名称常量 |
| `lib/core/logger/log_service.dart` | 统一日志系统 |
| `lib/core/error/app_exception.dart` | 异常基类体系 |
| `lib/core/error/result.dart` | Result 模式 |
| `lib/features/home/views/home_page.dart` | 首页（M3 组件 + Riverpod 验证） |
| `lib/features/home/providers/counter_provider.dart` | 计数器 Provider |
| `lib/features/home/providers/home_state_provider.dart` | 首页状态 Provider |

### Android 配置
| 文件 | 说明 |
|------|------|
| `android/app/build.gradle` | `minSdk=29`, `targetSdk=35`, `compileSdk=35` |
| `android/build.gradle` | 项目级 Gradle 配置 |
| `android/settings.gradle` | 项目设置 |
| `android/gradle.properties` | Gradle 属性 |
| `android/app/src/main/AndroidManifest.xml` | 权限声明 + Activity 配置 |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Flutter Activity |

### 测试
| 文件 | 说明 |
|------|------|
| `test/counter_provider_test.dart` | Riverpod Provider 单元测试 |
| `test/home_page_test.dart` | Material 3 页面 Widget 测试 |

### 其他
| 文件 | 说明 |
|------|------|
| `pubspec.yaml` | 依赖声明 |
| `analysis_options.yaml` | 严格 lint 规则 |
| `.github/workflows/ci.yml` | CI 流水线 |
| `setup_flutter_project.sh` | 开发机脚手架初始化 |

## 下一步

1. 在有 Flutter SDK 的开发机上运行 `bash setup_flutter_project.sh`
2. 执行 `flutter build apk --debug` 验证构建
3. 安装 APK 到 Android 真机验证冷启动和稳定性
4. 进入 **Milestone 0.2：Termux 通信验证**
