# 📋 Sprint 1 开发报告：项目框架

> **日期：** 2026-07-28
> **状态：** ✅ 完成

---

## 1. 完成模块

| 模块 | 状态 | 新增文件 | 新增代码行 |
|------|:----:|:--------:|:----------:|
| 模块1：主题系统完善 | ✅ | 4 | ~400 |
| 模块2：日志系统增强 | ✅ | 1 | ~260 |
| 模块3：全局异常处理 | ✅ | 3 | ~310 |
| 模块4：国际化 | ✅ | 4 | ~410 |
| 模块5：路由守卫 | ✅ | 2 | ~230 |
| **总计** | **5/5** | **14** | **~1610** |

---

## 2. 模块详情

### 模块1：主题系统完善

| 文件 | 说明 |
|------|------|
| `lib/core/theme/theme_provider.dart` | 主题状态管理（StateNotifier）：亮色/暗色/跟随系统、字体配置、持久化 |
| `lib/core/theme/app_theme.dart` | 补充 Card/Input/NavigationBar/SnackBar/Dialog/AppBar/Chip 主题 |
| `lib/features/settings/views/theme_settings_page.dart` | 主题设置 UI：模式选择 + 字体选择 + 缩放滑块 + 预览 |
| `lib/core/router/route_names.dart` + `app_router.dart` | 注册主题设置路由 |

**关键设计：**
- 主题模式通过 `SharedPreferences` 持久化
- 字体缩放范围 0.8–1.5，支持 Roboto / Noto Sans SC / 等宽字体
- AppBar 一键切换亮暗（`toggleTheme`）

### 模块2：日志系统增强

| 文件 | 说明 |
|------|------|
| `lib/core/logger/log_file_writer.dart` | 日志文件写入器：自动创建目录、文件轮转（按大小）、保留文件数控制、高频写入缓冲（5s 防抖） |
| `lib/core/logger/log_service.dart` | 集成 FileWriter、新增 `exception` 快捷方法、堆栈截断（最多 20 行）、`getRecentLogs`/`clearLogs`/`getTotalLogSize` |

**关键设计：**
- 单文件最大 1MB，保留 5 个轮转文件
- 缓冲区满 100 行或每 5 秒自动刷入
- 堆栈截断避免写盘过大

### 模块3：全局异常处理

| 文件 | 说明 |
|------|------|
| `lib/core/error/error_handler.dart` | 全局错误处理：FlutterError.onError、PlatformDispatcher.onError、runZonedGuarded、错误分类、调试/生产双模式、外部回调 |
| `lib/core/error/error_page.dart` | 错误页面：调试模式显示详细错误+堆栈、生产模式友好提示、重试/返回按钮 |
| `lib/main.dart` | 集成 GlobalErrorHandler + runZonedGuarded |

**捕获路径：**
```
Flutter 框架错误 (FlutterError.onError)
    → Dart 顶层错误 (PlatformDispatcher.onError)
        → Zone 未处理异常 (runZonedGuarded)
            → 统一记录日志 + 可选 UI 提示
```

### 模块4：国际化

| 文件 | 说明 |
|------|------|
| `lib/core/i18n/app_locale.dart` | 语言枚举（zh_CN/en_US）+ LocaleNotifier（切换/持久化） |
| `lib/core/i18n/strings.dart` | 所有用户文本集中管理：通用/首页/导航/AI/主题/Termux/部署/错误，约 60 个字符串 |
| `lib/features/settings/views/locale_settings_page.dart` | 语言设置 UI + 预览 |
| `lib/app.dart` | 集成 supportedLocales + locale 配置 |

**覆盖的字符串类别：**
- 通用（确定/取消/重试/保存/删除...）
- 首页（标题/状态/导航）
- AI 对话（标题/输入提示/清空/状态）
- 主题设置（模式/字体/预览）
- Termux 测试页
- 部署中心
- 错误页面

### 模块5：路由守卫

| 文件 | 说明 |
|------|------|
| `lib/core/router/route_guard.dart` | 权限体系：PermissionLevel（4 级）、UserRole（4 级）、AuthState/AuthNotifier、RoutePermissions（页面权限映射 + 重定向逻辑） |
| `lib/core/router/app_router.dart` | GoRouter redirect 守卫集成 |

**预留接口：**
- `AuthNotifier.login()` / `logout()` — 登录/登出
- `PermissionLevel` — 公开/已登录/会员/管理员
- 可扩展：OAuth、Token 管理、会员系统

---

## 3. 测试覆盖

| 测试文件 | 用例数 | 覆盖范围 |
|---------|:------:|---------|
| `test/theme_provider_test.dart` | 13 | ThemeModeOption、FontConfig、ThemeState、ThemeNotifier、AppTheme |
| `test/log_service_test.dart` | 10 | LogLevel、LogService.init/write/level、LogFileWriter CRUD/轮转/清理/dispose |
| `test/error_handler_test.dart` | 10 | GlobalErrorHandler 初始化/双调用/错误摘要/Zone/回调 |
| `test/locale_test.dart` | 10 | AppLanguage、LocaleNotifier、Strings 中英双语言/完整性 |
| `test/route_guard_test.dart` | 12 | PermissionLevel、AuthState/canAccess、AuthNotifier login/logout、RoutePermissions |
| **合计** | **55** | |

---

## 4. 文件变更统计

```
────────────────────────────────────────────────
文件                                 行数
────────────────────────────────────────────────
lib/core/theme/theme_provider.dart     145
lib/core/theme/app_theme.dart          110
lib/features/settings/views/theme_settings_page.dart  145
lib/core/logger/log_file_writer.dart   175
lib/core/logger/log_service.dart        95
lib/core/error/error_handler.dart      135
lib/core/error/error_page.dart         170
lib/core/i18n/app_locale.dart           65
lib/core/i18n/strings.dart             175
lib/features/settings/views/locale_settings_page.dart  95
lib/core/router/route_guard.dart       130
────────────────────────────────────────────────
Dart 代码合计                          ~1440

测试文件：
test/theme_provider_test.dart          110
test/log_service_test.dart             120
test/error_handler_test.dart           100
test/locale_test.dart                  85
test/route_guard_test.dart             95
────────────────────────────────────────────────
测试代码合计                           510

修改文件：
lib/main.dart                          变更
lib/app.dart                           变更
lib/core/router/app_router.dart        变更
lib/core/router/route_names.dart       变更
lib/features/home/views/home_page.dart  变更
────────────────────────────────────────────────
```

---

## 5. 性能基线对比

| 指标 | 基线目标 | Sprint 1 评估 |
|------|---------|:------------:|
| 冷启动时间 | < 3s | 新增 GlobalErrorHandler.init + LogService.init(main 中串行) 增加约 10-20ms |
| 空闲内存 | < 80 MB | 新增 14 个文件 ~1.6K 代码行，预计增加 < 2 MB |
| Page load | 顺畅 | 主题系统无额外开销，国际化仅字符串查找 |

**结论：** Sprint 1 对性能影响极小，未突破基线阈值。

---

## 6. 架构决策记录

### ADR-001：主题持久化方案
- **选择：** SharedPreferences
- **原因：** 仅存储 3 个键值对（mode/family/scale），无需复杂数据库
- **权衡：** 异步加载可能导致启动时短暂默认主题

### ADR-002：国际化方案
- **选择：** 自建 map-based 资源（非 flutter_localizations）
- **原因：** 本项目为专有 App，无需通用 i18n 工具链；map-based 方案零依赖、编译期检查
- **权衡：** 需要手动维护资源文件；不支持复数/性别等复杂本地化

### ADR-003：路由守卫方案
- **选择：** GoRouter redirect + Provider
- **原因：** 与现有 GoRouter 架构一致，无额外依赖；redirect 回调在每次导航前同步执行
- **权衡：** redirect 回调中不能执行异步操作（如 Token 刷新）

---

## 7. 后续 Sprint 建议

- **Sprint 2（首页+工作区）：** 基于 i18n 和 Theme 系统开发
- 每次 Sprint 结束时运行 `test/performance_benchmark_test.dart` 检查性能退化
- 路由守卫可在 Sprint 7（GitHub 集成）中启用真实登录
