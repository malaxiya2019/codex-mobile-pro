# 📦 Changelog

## [Unreleased]

### 🏗️ Sprint 3：项目管理和文件系统 ✅

#### 🚀 项目创建系统
- `features/project/models/project_template.dart` — ProjectTemplateType/TemplateVersion/ProjectTemplate/ProjectCreateConfig/ProjectCreateResult/ProjectInfo 完整数据模型，JSON 序列化
- `features/project/services/project_generator.dart` — `TemplateGenerator` 抽象基类 + `ProjectGeneratorService` 统一管理，模板与生成逻辑分离
- `features/project/services/templates/flutter_template_generator.dart` — Flutter 项目创建（flutter create + 回退结构）
- `features/project/services/templates/rust_template_generator.dart` — Rust 项目创建（cargo init + 回退结构）
- `features/project/services/templates/python_template_generator.dart` — Python 项目创建（venv + 完整目录结构）
- `features/project/providers/project_provider.dart` — ProjectNotifier 状态管理，SharedPreferences 持久化

#### 📁 文件浏览系统
- `features/file/services/file_service.dart` — 懒加载目录树、异步文件读取（1MB限制）、前N行预览、文件搜索（50条限制）、30+ 文件类型图标识别
- `features/file/providers/file_provider.dart` — FileBrowserNotifier 状态管理（浏览/树展开/搜索/导航）
- `features/file/views/file_browser_page.dart` — 文件浏览器 UI（路径导航、文件树、内容查看器、搜索）

#### 🌐 国际化扩展
- `lib/core/i18n/strings.dart` — 新增 22 条字符串（文件浏览 11 + 项目创建 11）

#### 🧪 测试
- `test/project_template_test.dart` — 15 个用例（模型/序列化/容错）
- `test/project_generator_test.dart` — 12 个用例（注册/模板管理/类型验证）
- `test/file_service_test.dart` — 16 个用例（文件条目/目录/读取/搜索/树节点）

---

### 🏗️ Sprint 2：工作区管理 ✅
### 🏗️ Sprint 1：项目框架 ✅
