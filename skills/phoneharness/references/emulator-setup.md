# PhoneHarness 模拟器环境搭建参考

来源：`docs/emulator-setup.md`、`docs/required-apps.md`、`scripts/`。目标：不发布本地 AVD 镜像、app 数据、凭证与第三方 APK 的前提下可复现评测环境。

## 参考 AVD（每个 slot 一个模拟器）

| 设置 | 参考值 |
|---|---|
| AVD 名 | `AndroidWorldAvd` |
| 设备 profile | `pixel_6` |
| 系统镜像 | `system-images;android-33;google_apis_playstore;arm64-v8a` |
| Android API | 33 |
| RAM | 2048 MB |
| 数据分区 | 32G 推荐（16G 轻量 smoke 最低，24G 更稳妥） |
| 屏幕 | 1080x2400，Pixel 6 密度；GUI helper 假设 1080 宽坐标 |
| 启动参数 | `-no-snapshot -no-audio -no-boot-anim` |

```bash
scripts/create_avd.sh --install-sdk --start            # 默认 emulator-5554
scripts/create_avd.sh --name AndroidWorldAvd_2 --serial emulator-5556 --start   # 并行 slot
```

`scripts/setup_emulator.sh` 与 `scripts/install_apps.sh` 完成 Termux、Termux:API、ADBKeyboard、PhoneHarness 端口连线与必备 app 安装。app 清单参考 `config/apk-manifest.example.tsv` 与 `docs/required-apps.md`。

## 运行时布局（单模拟器默认）

| 组件 | 位置 | 默认 |
|---|---|---|
| gui_proxy | host | `127.0.0.1:8919` |
| PhoneHarness server | 模拟器 Termux | 设备端口 `8920` |
| host→device | adb forward | `host:8920 -> device:8920` |

多 slot 时每个模拟器独立一组：serial emulator-5554+N*2、server :8920+N*10、gui :8919+N*10。

## 环境变量

```bash
export OPENAI_BASE_URL="<openai-compatible-base-url>"
export OPENAI_API_KEY="<api-key>"
export PHONEHARNESS_GUI_API_URL="<可选 GUI 模型 base-url>"
export PHONEHARNESS_GUI_API_KEY="<可选 GUI 模型 api-key>"
```

console 默认 `--base-url http://10.0.2.2:8918/v1 --api-key test`；`--gui-model` 必填，无隐藏 fallback；`--gui-mode delegated|flat`（默认 delegated）；`--serial` 读 `ADB_SERIAL`。

## vdisplay-helper（Android 虚拟显示）

`vdisplay-helper/` 是 Java App 源码：`VDService`（虚拟显示服务）、`ScreenshotReceiver`（截图接收）、`PermActivity`（权限授予）。构建：`vdisplay-helper/build.sh`。用途：在无物理屏幕的模拟器会话中提供可控虚拟显示，供截图驱动 GUI。

## 注意事项

- 生成 trace、本地模型输出、第三方 APK、登录态 app、模拟器快照、私有 host 服务部署都不进 git。
- 用 `docs/emulator-setup.md` + `docs/required-apps.md` 重建环境；app 与凭证本地获取。
- 排查环境问题先跑 `scripts/collect_emulator_info.sh` 收集模拟器信息。
