# Contributing / 参与贡献

欢迎通过 Issues 报告问题、提出功能建议，或通过 Pull Request 提交修复。

## Before opening an issue

- Include the app version, OS version, platform and minimal reproduction steps.
- Distinguish native macOS behavior from the Windows Electron implementation.
- Never upload personal backups, complete usage histories, credentials or sensitive screenshots to a public issue.
- Do not post a vulnerability with an exploitable secret in a public issue. Use GitHub's private vulnerability reporting feature if enabled; otherwise report a minimal non-sensitive description without secret values.

## Development

macOS requires macOS 13+ and Swift 5.9+:

```sh
swift test
bash scripts/build-app.sh
```

Windows development requires Node.js 22+; package installers on Windows:

```sh
cd desktop
npm ci
npm test
npm run check
npm run build:win
```

Website (Python 3 standard library):

```sh
python3 tools/build_site.py
python3 -m unittest discover -s Tests -v
```

Edit website content in `tools/build_site.py`, then regenerate the static `site/` output. Keep Chinese/English wording, privacy caveats, release versions and machine-readable product facts consistent. Do not fabricate reviews, medical claims or measured performance.

## Pull requests and license

Keep changes focused, add a failing regression for bugs, run the relevant tests and describe what was verified. Do not submit extracted proprietary source/assets or another person's data. By submitting a contribution for inclusion, you agree that your original contribution is provided under this repository's MIT License, unless you explicitly state otherwise before acceptance. Third-party components keep their own licenses; identify and preserve their notices.

No CLA or copyright assignment is required by this document.
