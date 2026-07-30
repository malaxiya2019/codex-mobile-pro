# Ubuntu Runtime Supply Chain — Phase 0.5 决策记录

> 日期：2026-07-30
> 状态：✅ 调查完毕，可进入 Phase 1

---

## 1. Rootfs

| 属性 | 值 |
|------|------|
| 来源 | `termux/proot-distro` GitHub Release |
| 版本 | v4.18.0 |
| 发行版 | Ubuntu 24.04.1 LTS (Noble Numbat) |
| 架构 | aarch64 (ARM64) |
| 格式 | tar.xz |
| 大小 | 64,133,552 bytes (~62 MB) |
| 文件名 | `ubuntu-noble-aarch64-pd-v4.18.0.tar.xz` |
| URL | https://github.com/termux/proot-distro/releases/download/v4.18.0/ubuntu-noble-aarch64-pd-v4.18.0.tar.xz |
| SHA-256 | `91acaa786b8e2fbba56a9fd0f8a1188cee482b5c7baeed707b29ddaa9a294daa` |
| 顶级前缀 | `ubuntu-noble-aarch64/`（提取需 `stripComponents=1`） |
| 总文件数 | 12,684 |
| License | 标准 Ubuntu 包许可证（GPLv2+ / MIT 等混合），可再分发 |
| 包含组件 | `/usr/bin/bash`, `/usr/bin/sh`, `/usr/bin/apt`, `/usr/bin/dpkg`, `/usr/bin/python3`, `apt sources` 已配置为 `ports.ubuntu.com` |
| 分发方式 | App 运行时首次下载（GitHub Releases），不捆绑到 APK |

**验证方法**：
- HTTP HEAD：200 OK, `accept-ranges: bytes`
- XZ magic bytes 验证通过
- 完整 SHA-256 校验通过
- tar 列表确认关键组件存在

---

## 2. Proot Loader

| 属性 | 值 |
|------|------|
| 来源 | `termux/proot` via Termux package repository |
| 版本 | 5.1.107.89 |
| 架构 | aarch64 (Android NDK r29, API 24) |
| 下载 URL | https://packages.termux.dev/apt/termux-main/pool/main/p/proot/proot_5.1.107.89_aarch64.deb |
| 包类型 | .deb (ar + data.tar.xz) |
| License | GPLv2 |
| 是否可随 App 分发 | 是，从 Termux 官方仓库下载 |
| 提取后路径 | `usr/bin/proot` + `usr/libexec/proot/loader` + `usr/libexec/proot/loader32` |

### 组成文件

#### proot 主程序
- 路径：`usr/bin/proot`
- 大小：239,368 bytes
- ELF 类型：ELF 64-bit LSB shared object, ARM aarch64
- 链接方式：dynamically linked, interpreter `/system/bin/linker64`
- 构建工具：NDK r29 (14206865)
- 符号状态：stripped
- SHA-256：`6ffdff4117c571d07aa7e6f940001f050c97adb920660c984b72d4a537b4f60a`

#### loader (64-bit)
- 路径：`usr/libexec/proot/loader`
- 大小：18,136 bytes
- ELF 类型：ELF 64-bit LSB executable, ARM aarch64
- 链接方式：statically linked, stripped
- SHA-256：`44ef39c1e1a18c09f6e4c4b5d6f8bba82d30596598bd155ec162d05c5122ff04`

#### loader32 (32-bit)
- 路径：`usr/libexec/proot/loader32`
- 大小：6,244 bytes
- ELF 类型：ELF 32-bit LSB executable, ARM, EABI5
- 链接方式：statically linked, stripped
- SHA-256：`25f6bd90bc5a3d3088026289a0d3eaf3e502bd2b00e5cb74fadd9791132efa34`

### proot 启动参数（参考 termux-chroot）

```
proot \
  --kill-on-exit \
  -b /system:/system \
  -b /vendor:/vendor \
  -b /data:/data \
  -b /sbin:/sbin -b /root:/root \
  -b /apex:/apex \
  -b /linkerconfig/ld.config.txt:/linkerconfig/ld.config.txt \
  -b /property_contexts:/property_contexts \
  -b /storage:/storage \
  -b $PREFIX:/usr \
  -b $PREFIX/bin:/bin \
  -b $PREFIX/etc:/etc \
  -b $PREFIX/lib:/lib \
  -b $PREFIX/share:/share \
  -b $PREFIX/tmp:/tmp \
  -b $PREFIX/var:/var \
  -b /dev:/dev \
  -b /proc:/proc \
  --cwd=/home \
  -r $PREFIX/.. \
  /usr/bin/bash -l
```

**关键说明**：
- 当前 Termux 版本的 proot 是独立的 ELF binary，可以直接用 Process.start() 启动
- 与 OperitTerminalCore 的 `libproot.so` + JNI 方案不同，我们不需要编译 NDK 库
- 通过 `PROOT_LOADER` 环境变量指向 loader 文件

---

## 3. Fake Sysdata（原理分析，非复制）

### 问题

Android 的 `/proc` 文件系统限制严格。proot 无法从 Android 的 `procfs` 读取正确的数据。某些工具（如 `ps`, `uptime`, `neofetch`）需要读取 `/proc/stat`, `/proc/uptime`, `/proc/loadavg` 等文件。

### 解决方案（proot 机制）

proot 会在读取 `/proc/stat` 时，透明地重定向到 `/proc/.stat`（注意前缀 `.`）。因此只需要在 rootfs 中创建带 `.` 前缀的 fake 文件。

### 需要创建的文件

| 文件 | 用途 | 内容类型 |
|------|------|----------|
| `/proc/.loadavg` | CPU 平均负载 | 静态示例值 |
| `/proc/.stat` | CPU 统计（含核心数） | 多核心示例值 |
| `/proc/.uptime` | 系统运行时间 | 固定值 |
| `/proc/.version` | 内核版本 | 格式化为 Linux 版本字符串 |
| `/proc/.vmstat` | 虚拟内存统计 | 完整示例值 |
| `/proc/.sysctl_entry_cap_last_cap` | 能力上限 | `40` |
| `/proc/.sysctl_inotify_max_user_watches` | inotify 上限 | `4096` |

### 设计原则（我们自己的实现）

- 使用 Dart 代码（而非 shell 脚本）在启动前生成这些文件
- CPU 核心数从 Android `Build.SUPPORTED_ABIS` 获取（实际设备）
- 文件内容使用固定模板值的组合，不需要动态更新
- 只在首次初始化 rootfs 时创建一次
- 函数名：`SysDataSetup.setup(rootfsPath)`

### 不实施复制

不复制 OperitTerminalCore 的 `setup_fake_sysdata.sh`（GPLv3）。仅参考其创建的文件列表和值格式，重新实现为 Dart 代码。

---

## 4. Artifact Manifest（设计提案）

```json
{
  "runtimeType": "ubuntu_rootfs",
  "version": "24.04",
  "codename": "noble",
  "arch": "aarch64",
  "rootfs": {
    "url": "https://github.com/termux/proot-distro/releases/download/v4.18.0/ubuntu-noble-aarch64-pd-v4.18.0.tar.xz",
    "sha256": "91acaa786b8e2fbba56a9fd0f8a1188cee482b5c7baeed707b29ddaa9a294daa",
    "size": 64133552,
    "format": "tar.xz",
    "stripComponents": 1
  },
  "proot": {
    "binary": {
      "url": "https://packages.termux.dev/apt/termux-main/pool/main/p/proot/proot_5.1.107.89_aarch64.deb",
      "sha256": "6ffdff4117c571d07aa7e6f940001f050c97adb920660c984b72d4a537b4f60a",
      "size": 95784,
      "format": "deb",
      "extractPath": "usr/bin/proot"
    },
    "loader": {
      "url": "https://packages.termux.dev/apt/termux-main/pool/main/p/proot/proot_5.1.107.89_aarch64.deb",
      "sha256": "44ef39c1e1a18c09f6e4c4b5d6f8bba82d30596598bd155ec162d05c5122ff04",
      "extractPath": "usr/libexec/proot/loader"
    },
    "loader32": {
      "url": "https://packages.termux.dev/apt/termux-main/pool/main/p/proot/proot_5.1.107.89_aarch64.deb",
      "sha256": "25f6bd90bc5a3d3088026289a0d3eaf3e502bd2b00e5cb74fadd9791132efa34",
      "extractPath": "usr/libexec/proot/loader32"
    }
  }
}
```

---

## 5. 当前代码迁移方案

### 可复用的组件

| 组件 | 是否可以复用 | 说明 |
|------|-------------|------|
| `RuntimeManager` | ✅ 保持接口 | 接口稳定，只替换底层 Installer |
| `RuntimeEnvironment` | ✅ 需扩展 | 增加 proot 所需的 `PROOT_LOADER`, `LD_LIBRARY_PATH` |
| `RuntimeManifest` | ✅ 需扩展 | 增加 `ArtifactType.rootfs` 类型 |
| `ArtifactManager` | ✅ 可直接复用 | download / SHA256 / extract 逻辑完全通用 |
| `TerminalService` | ✅ 保持不动 | 不需要修改 PTY 架构 |
| `Deployment Center` | ✅ 保持 UI | 状态模型已正确，只需替换后端 Installer |
| `RuntimeDetector` | ⚠️ 需修改 | 增加 Ubuntu rootfs 检测逻辑 |

### 需要新增的组件

| 组件 | 职责 |
|------|------|
| `UbuntuRuntimeInstaller` | 管理 rootfs+proot 的下载、校验、解压、初始化 |
| `UbuntuRuntime` | rootfs + proot 的统一表示 |
| `RootfsManager` | 管理 rootfs 的生命周期（解压、校验、修复） |
| `SysDataSetup` | 创建 fake /proc 文件（Dart 实现） |
| `ProotRuntime` | 构建 proot 启动命令和环境变量 |

### 需要废弃的组件

| 组件 | 状态 | 说明 |
|------|------|------|
| `RuntimeInstaller` (现有 .deb 逻辑) | ⚠️ 保留不删除 | 仅标记为 deprecated，Phase 2 再移除 |
| `RuntimeManifest.node` | ⚠️ 标记为 deprecated | 不再下载单包 Node.js |

### 数据目录设计

```
<app filesDir>/runtime/
├── ubuntu/
│   ├── rootfs/            # 解压后的 Ubuntu rootfs
│   │   ├── bin -> usr/bin
│   │   ├── etc/
│   │   ├── usr/
│   │   ├── root/
│   │   ├── tmp/
│   │   └── proc/           # fake sysdata 文件
│   │       ├── .stat
│   │       ├── .loadavg
│   │       ├── .uptime
│   │       ├── .version
│   │       ├── .vmstat
│   │       ├── .sysctl_entry_cap_last_cap
│   │       └── .sysctl_inotify_max_user_watches
│   ├── bin/                # proot loader 文件
│   │   ├── proot
│   │   └── libexec/
│   │       └── proot/
│   │           ├── loader
│   │           └── loader32
│   ├── metadata.json       # 安装元数据
│   └── logs/               # 安装日志
```

---

## 6. Phase 1 实施计划

### Step 1: 新增 UbuntuRuntimeManifest

在 `runtime_manifest.dart` 中新增：
- `ArtifactType.rootfs` 和 `ArtifactType.proot`
- `RuntimeManifest.ubuntu` 静态定义
- 使用上述验证过的 URL 和 SHA256

### Step 2: 实现 SysDataSetup

新建 `sysdata_setup.dart`：
- 纯 Dart 实现 fake /proc 文件创建
- 不为每个文件单独写 shell 脚本
- 使用 `dart:io` File 操作

### Step 3: 实现 UbuntuRuntimeInstaller

新建 `ubuntu_runtime_installer.dart`：
- 继承或遵循现有 Installer 接口
- 复用 `ArtifactManager` 做下载/SHA256/解压
- Rootfs 提取使用 `stripComponents: 1`
- Proot .deb 提取使用 `stripComponents: 6`（与现有相同）
- 安装完成后调用 `SysDataSetup.setup()`

### Step 4: RuntimeEnvironment 扩展

在 `runtime_environment.dart` 中增加：
- Ubuntu 启动环境变量
- `PROOT_LOADER` 指向 loader 路径
- 正确的 PATH 构造

### Step 5: TerminalService/PTY 集成

- TerminalService 检测 `RuntimeManager` 的 Runtime 类型
- 如果 `UbuntuRuntime` 就绪，PTY 启动命令改为 proot
- 否则保持现有 `/system/bin/sh`

### 验收标准（Phase 1）

启动 Terminal 后执行：
```
uname -a
cat /etc/os-release
pwd
ls /
echo hello
```
全部成功。

---

## 7. License 说明

| 组件 | License | 分发注意事项 |
|------|---------|-------------|
| Ubuntu rootfs | 混合（GPLv2+, MIT, Apache 2.0） | 运行时从 proot-distro Release 下载，不捆绑 |
| proot binary | GPLv2 | 运行时从 Termux 仓库下载，不捆绑 |
| setup_fake_sysdata 概念 | 功能性操作，非版权保护 | 自行用 Dart 重新实现 |

---

## 8. 决策

**正式决定**：App 默认 Coding Runtime = **Ubuntu 24.04 Noble ARM64 rootfs + proot**

- ✅ Rootfs 来源已验证可用
- ✅ Proot-loader 来源已验证可用
- ✅ Fake sysdata 原理已理解，可自行实现
- ✅ 无需操作 GPLv3 代码
- ✅ 无需捆绑到 APK
- ⚠️ .deb 单包安装器标记为 deprecated，暂不删除

**下一步：Phase 1 实施 — 实现 UbuntuRuntimeInstaller 并接入 TerminalService**
