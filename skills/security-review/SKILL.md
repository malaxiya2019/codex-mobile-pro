---
name: security-review
description: 专项安全排查（security review）。扫描代码/仓库中的真实敏感信息风险：token、API key、secret、密码、私钥、签名 keystore、明文存储。当用户要求「安全审查」「security-review」「排查泄露」「检查敏感信息」时使用。发现真实凭证时立即停止修改，只报告位置。
---

# 安全专项审查

目标：找出真实风险并分级，不制造恐慌，不修改代码。

## 扫描范围

1. **硬编码凭证**
   - 全仓库 grep：`token|api[_-]?key|secret|password|passwd|private[_-]?key|BEGIN .*PRIVATE KEY`
   - 排除测试 fixture、占位符、文档示例

2. **git 跟踪的敏感文件**
   - `git ls-files` 过滤：`.env*|*.keystore|*.jks|*.p12|*.pem|*.key|secrets.*`
   - 检查 `.gitignore` 是否该忽略而未忽略

3. **签名与构建链**
   - Android/iOS 签名配置（`build.gradle`/`key.properties`/`exportOptions.plist`）
   - keystore 是否入库、密码是否明文、是否复用 debug 签名
   - CI 中 secret 是否硬编码（`secrets.X` 用法检查）

4. **存储位置**
   - token/凭证存哪：SharedPreferences（明文）vs flutter_secure_storage/Keychain/KeyStore
   - 日志是否打印凭证

5. **公开仓库暴露面**
   - `gh repo view --json visibility` 确认仓库是否 public
   - public 仓库中任何真实凭证 = 已泄露，按高优先级处理

## 分级

- **S1 高**：公开仓库中的真实私钥/签名密钥/可用的完整凭证 → 立即停止修改，报告位置 + 影响 + 修复方案（需用户决策）
- **S2 中**：明文存储敏感数据、弱密钥、可改进的存储方案 → 报告 + 建议
- **S3 低**：设计使然的明文（如 CLI 的 .env）、占位符 → 说明即可

## 输出格式

- 每项：位置（文件:行）+ 风险描述 + 分级 + 修复建议
- 已确认干净的范围列表（查过但没问题的）

## 约束

- 发现真实凭证：**不修改、不提交、不公开**，只报告
- 分级基于事实，不夸大
