# FFI 原生加速参考

> 来源：Firecrawl `apps/api/native/src/` — Rust napi 架构

## 模式描述

Firecrawl 将 CPU 密集型操作（爬虫过滤、HTML 解析、PDF 处理、文档转换）用 Rust 编写，
通过 N-API (`napi-derive`) 编译为 Node.js 原生插件，性能提升 10-100x。

## Flutter 对应方案

Flutter 有 `dart:ffi` 和 **Native Assets**（Flutter 3.10+），可以用 C/C++/Rust 编写原生扩展。

### 候选场景

```dart
// ─── 场景 1：大文件 SHA256 校验 ───
// 当前：Dart 逐块读取 + sha256.convert()
// 优化：FFI 调用 BoringSSL（Android 自带）
// 预期：60MB rootfs 校验从 ~2s 降到 ~0.3s

// ─── 场景 2：tar.xz 解压 ───
// 当前：找系统 tar 命令
// 优化：FFI 用 libarchive / liblzma
// 预期：解压速度提升 3-5x，且内存占用更可控

// ─── 场景 3：Deb 包解析 ───
// 当前：Dart 解析 ar 归档 + tar.xz
// 优化：FFI 用 libarchive
// 预期：解析时间减半
```

### 但当前不需要

性能瓶颈分析（按当前 codex-mobile-pro 的流程）：

| 操作 | 耗时 | 瓶颈类型 | 优化优先级 |
|:---|:---|:---|:---|
| 网络下载（60MB rootfs） | 10-60s | I/O | — |
| SHA256 校验 | ~2s | CPU | 低 |
| tar.xz 解压 | 5-15s | CPU+I/O | 中 |
| 安装（文件复制/link） | <1s | I/O | 低 |

**结论**：当前瓶颈在网络 I/O，不是 CPU。FFI 优化可以先不做，
等解压或校验成为瓶颈时再引入。

### 如果未来需要

```rust
// Rust 端（类似 Firecrawl 的 napi 模式）
#[napi]
pub fn sha256_file(path: String) -> napi::Result<String> {
    use sha2::{Sha256, Digest};
    use std::fs::File;
    use std::io::Read;
    
    let mut file = File::open(&path)
        .map_err(|e| napi::Error::from_reason(e.to_string()))?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 8192];
    
    loop {
        let n = file.read(&mut buffer)
            .map_err(|e| napi::Error::from_reason(e.to_string()))?;
        if n == 0 { break; }
        hasher.update(&buffer[..n]);
    }
    
    Ok(format!("{:x}", hasher.finalize()))
}
```

Flutter 端通过 `dart:ffi` 或 `package:ffigen` 调用。

## 关键决策

| 场景 | 优先级 | 理由 |
|:---|:---|:---|
| SHA256 FFI | 低 | 当前 Dart 实现够用 |
| tar.xz FFI | 中 | 解压 60MB rootfs 时可能 OOM |
| Deb 解析 FFI | 低 | 只有少量 .deb 需要解析 |
| DNS 查询优化 | 无需 FFI | Dart `InternetAddress.lookup` 已调用系统 API |
