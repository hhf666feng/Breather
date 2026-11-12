# Third-party notices and scope

Breather's original source code and original documentation in this repository are licensed under the [MIT License](LICENSE). This grant does not relicense third-party software, operating-system frameworks, or external linked material. It does not grant third-party trademark rights or imply endorsement by Apple, Microsoft, GitHub, Electron, AOA, AAO, or any other application.

## macOS

The native macOS implementation uses Swift, SwiftUI, AppKit and operating-system APIs. Their SDK/runtime terms remain with their respective owners. No proprietary source or assets extracted from another application are distributed in this public repository.

## Windows

The Windows distribution embeds Electron, which includes Chromium, Node.js and other components with their own licenses and notices. Electron is MIT-licensed, but that does not mean all bundled Chromium dependencies have the same license. Preserve Electron's distributed license files and Chromium third-party license notices when redistributing a packaged Windows application.

Electron and electron-builder versions are pinned in `desktop/package.json`; transitive dependency versions and declared licenses are recorded in `desktop/package-lock.json`. The lockfile is an inventory, not a substitute for each dependency's actual license text. electron-builder and other build tools are governed by their own licenses.

## Design-method attribution

The initial independent brand/interface work used the unslop design-review method by Damir Sokolovsky ([@heydamir](https://x.com/heydamir)), distributed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). This is method attribution, not a claim that third-party skill content is included or relicensed as MIT. Breather's window-shaped mark and application assets were independently drawn for this project.

## Educational sources

The site links to AOA/AAO educational guidance. Those external publications remain copyrighted by their owners; MIT covers Breather's original explanatory text, not the external articles. No medical endorsement or efficacy claim is made.
