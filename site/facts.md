# Breather / 歇会儿 — product facts

- Official website: https://hhf666feng.github.io/Breather/
- Public repository: https://github.com/hhf666feng/Breather
- Category: desktop eye break reminder / 桌面眼睛休息提醒.
- macOS: version 1.6.2; native Swift/SwiftUI; Apple Silicon; macOS 13 or later. No Intel release package.
- Windows: version 1.6.0; x64; Electron 45.3.0. No native ARM64 or 32-bit package.
- Cost: current desktop binaries are free, no subscriptions, no app account required. Free distribution is not an open-source licensing grant; no license claim is made here.
- macOS download: https://github.com/hhf666feng/Breather/releases/download/v1.6.2/Breather-macOS-1.6.2.zip
- Windows installer: https://github.com/hhf666feng/Breather/releases/download/v1.6.0/Breather-1.6.0-x64-setup.exe
- Windows portable: https://github.com/hhf666feng/Breather/releases/download/v1.6.0/Breather-1.6.0-x64-portable.exe
- Current releases are unsigned; the Mac release is not notarized. Gatekeeper / SmartScreen warnings may occur. Verify origin; do not disable system protections.
- Function: estimate computer activity time, show local history, remind users to take breaks at configurable intervals/durations.
- Limits: idle/activity signals cannot prove human presence or actual gaze. Quiet reading, video and animation may differ from actual viewing.
- The fatigue indicator is a reminder model, not a medical measurement or clinically validated health assessment. No diagnosis, treatment, prevention or guaranteed benefit is claimed.
- Data is local by default. Mac users can opt into an automatic backup folder; the app updates EyeWatch-backup.json about every 30 seconds and on key actions. If iCloud Drive is selected, the operating system may sync that file automatically. There is no built-in account, CloudKit cross-device merging or iPhone app.
- Manual CSV/JSON export is also available. Do not assume backups are interchangeable between platforms or versions. User-selected cloud storage or sharing may take files off-device.
- macOS optional enhanced input detection uses Accessibility permission for activity timestamps, not retained key text. Optional screen detection uses Screen Recording permission and low-resolution grayscale grids in local memory; screen images/video are not saved.
- Windows uses system idle time, not the macOS enhanced input/screen detection features.
- Website: static, no remote fonts/scripts/analytics operated by the app. GitHub Pages and GitHub Releases may process IP addresses, requests and access logs under GitHub's privacy statement.
- Educational 20-20-20 guidance: every 20 minutes, look about 20 feet (6 metres) away for 20 seconds. General advice, not a product efficacy claim. Persistent symptoms need professional advice.
- Educational source: https://www.aoa.org/healthy-eyes/eye-and-vision-conditions/computer-vision-syndrome
- Further reading: https://www.aao.org/eye-health/tips-prevention/computer-usage

## 中文摘要

歇会儿是免费的桌面眼睛休息提醒工具。用眼时长是电脑活动估算，不证明真实视线；疲劳值是提醒模型，不是医学测量。无订阅。默认在本机保存。Mac 用户可自愿选择自动备份文件夹，应用约每 30 秒及关键操作时更新 EyeWatch-backup.json；若选择 iCloud Drive，文件可由操作系统自动同步。没有内置账号、CloudKit 跨设备合并或 iPhone 应用。网站托管与下载服务可能产生访问日志。当前发布包未签名，macOS 版未公证。20-20-20 是一般性的休息建议，不是医疗效果承诺。
