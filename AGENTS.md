# codex-mobile-pro

手机上的 AI IDE — 一键部署、国内直连、中文交互。

## 技术栈

- Flutter / Dart（主框架）
- Android Native PTY（JNI forkpty / posix_openpt）
- Riverpod 状态管理
- go_router 路由
- GitHub Actions CI

## 当前阶段

Coding Runtime 链路 — 部署中心 / Runtime Manager / Ubuntu Runtime 集成。

### 已完成
- Terminal Native PTY（forkpty / posix_openpt）
- 多标签、ANSI、Job Control、Extra Keys、Copy/Paste
- Runtime Manager / Deployment Center 架构
- 状态模型（installed/missing/failed/blocked/unsupported）
- SafeArea 底部导航修复
- Obsidian Vault 记忆系统

### 进行中
- CI 全绿通过
- Ubuntu Runtime (rootfs + proot) 集成
- Node.js / Git / Python 安装链路

## 架构原则

### Runtime 安装
- Runtime Manager 不负责实现 Linux，只负责检测 → 初始化 → 启动 → 状态管理
- Ubuntu rootfs 负责 apt → 包管理 → Node/Python/Git
- 安装必须真实验证（`node --version` 等），禁止假安装
- 所有环境变量由 `RuntimeEnvironment` 统一构建
- 不改 `/system` 系统目录，不改 Terminal / PTY 架构

### 安装前网络预检
- 安装开始前必须执行 `NetworkDetector.quickCheck()` 快速 DNS 检查
- DNS 失败时不得继续安装，必须显示可操作指引（切换网络/配置 DNS）
- 网络状态在 UI 中作为 `basic` 类别第一个卡片展示

### 状态语义
- `notInstalled`=未安装（⬜），`installed`=已安装（✅）
- `failed`=安装失败（❌），`blocked`=依赖阻塞（⛔）
- `unsupported`=暂不支持自动安装（⚠️）
- UI 层不允许偷偷转换状态语义

## 关键文件

- `lib/runtime/runtime_manager.dart` — Runtime 管理器
- `lib/runtime/runtime_environment.dart` — 环境变量管理
- `lib/runtime/ubuntu_runtime_installer.dart` — Ubuntu Runtime 安装器
- `lib/features/deploy/views/deploy_page.dart` — 部署中心 UI
- `lib/features/deploy/providers/deploy_provider.dart` — 部署状态管理
- `lib/core/detector/detectors/network_detector.dart` — 网络连通性检测器（DNS + HTTP 预检）

## 更新协议

工作产出重要结论或任务状态变更时，更新：
- `~/Obsidian-Vault/System/Assistant/context.md` — 项目状态、里程碑
- `~/Obsidian-Vault/System/Assistant/preferences.md` — 偏好变更（如新增约束）
