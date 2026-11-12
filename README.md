# 歇会儿 · Breather

**用眼之间，留一段空白。 A pause between screen time.**

Breather 是面向 macOS 和 Windows 的本地用眼时长记录与休息提醒应用。Mac 使用 SwiftUI/AppKit，Windows 使用 Electron 托盘应用。无需订阅，下载包免费使用；源码公开可查，但本仓库目前未授予开源许可证，请勿将“公开源码”理解为任意再分发许可。

Breather is a local eye-break reminder and screen-time companion for macOS and Windows. Downloadable binaries are free of charge, without a subscription. Source is available for inspection; no open-source license has been assigned.

## 官网 / Website

[中文与 English 官网](https://hhf666feng.github.io/Breather/) · [下载与系统要求](https://hhf666feng.github.io/Breather/download/) · [FAQ](https://hhf666feng.github.io/Breather/faq/) · [隐私说明](https://hhf666feng.github.io/Breather/privacy/)

## 下载 / Downloads

| Platform | Version | Download |
|---|---|---|
| macOS 13+, Apple Silicon | 1.6.2 | [Mac ZIP](https://github.com/hhf666feng/Breather/releases/download/v1.6.2/Breather-macOS-1.6.2.zip) |
| Windows x64 | 1.6.0 | [Installer](https://github.com/hhf666feng/Breather/releases/download/v1.6.0/Breather-1.6.0-x64-setup.exe) · [Portable](https://github.com/hhf666feng/Breather/releases/download/v1.6.0/Breather-1.6.0-x64-portable.exe) |

Mac 应用未进行 Developer ID 签名／公证，Windows 未进行发行者签名，系统可能提示未知开发者。仅从本仓库下载并核对 Release 校验文件。Mac 1.6.2 修复系统拒绝 Dock 切换时导致的启动反馈循环；Windows 版本号独立。

## 功能 / Features

- 本地用眼时长与休息完成率、CSV 导出和手动备份恢复。
- 自定义工作／休息时长、星期与时段，20 分钟／20 秒为默认配置。
- 全屏、迷你窗口与系统通知；严格休息与算术题跳过策略。
- 关闭主窗口后继续在菜单栏／托盘监测；中英文即时切换。
- Mac ⌘W、⌘M、⌘,、⌘0、⌘⇧R、⌘Q；Windows Ctrl+W、Alt+F4、Ctrl+M、Ctrl+,、Ctrl+0、Ctrl+Shift+R、Ctrl+Q。
- Mac 可选辅助功能输入时间戳与屏幕变化检测，默认关闭，需明确系统授权。Windows 使用系统 idle，不提供这两项 Mac 权限增强。

The “fatigue” indicator is a timer-based estimate, not a medical measurement or gaze detection. System idle cannot establish whether a person is present. Breather is not a medical device; it does not diagnose or treat eye conditions.

## 隐私 / Privacy

应用核心记录保存在本机，不要求账户。Mac 数据位于 `~/Library/Application Support/EyeWatch/`，Windows 位于 `%APPDATA%/BreatherWindows/`。不记录输入文字，不使用摄像头；可选屏幕变化检测在内存中处理低分辨率差异，不保存录像。系统权限、通知、登录项和用户选择的 iCloud Drive 文件夹由操作系统管理。无内置跨设备云端合并或手机推送。

官网为无第三方脚本的静态页面；GitHub 托管／下载服务仍可能记录其基础访问日志。

## 构建与测试 / Build and test

Mac: Swift 5.9+, macOS 13+.

```sh
swift test
bash scripts/build-app.sh
open dist/Breather.app
```

Windows: Node.js 22+; use Windows for installer packaging.

```sh
cd desktop
npm ci
npm test
npm run check
npm start
npm run build:win
```

Site: Python 3 standard library, no frontend dependencies.

```sh
python3 tools/build_site.py
python3 -m unittest discover -s tests -v
```

## 关于此公开仓库

本仓库由审计后的独立源码快照开始，不包含内部研究资料、第三方应用原始提取、个人运行记录或私有开发历史。它保留原应用数据标识以兼容本机升级；并非与其他同名应用关联。

问题反馈请使用本仓库 [Issues](https://github.com/hhf666feng/Breather/issues)。请勿上传包含个人数据或系统截图的完整备份。
