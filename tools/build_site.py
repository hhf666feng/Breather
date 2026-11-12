#!/usr/bin/env python3
"""Render the dependency-free Breather site. No network requests or asset mutation."""
from html import escape
import json
from pathlib import Path
from urllib.parse import urlsplit
from xml.sax.saxutils import escape as xml_escape

ROOT = Path(__file__).resolve().parents[1]
ROUTES = ['', 'download/', 'faq/', 'privacy/', 'guidance/20-20-20/']
AOA = 'https://www.aoa.org/healthy-eyes/eye-and-vision-conditions/computer-vision-syndrome'
AAO = 'https://www.aao.org/eye-health/tips-prevention/computer-usage'

CSS = '''
:root{color-scheme:light;--paper:#F8F7F4;--ink:#242523;--rust:#A34F37;--muted:#62635C;--line:#D9D8D0;--white:#fff;--soft:#EEEBE4;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;color:var(--ink);background:var(--paper);font-synthesis:none}
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;font-size:17px;line-height:1.75}a{color:var(--rust);text-underline-offset:4px}a:hover{text-decoration-thickness:2px}a:focus-visible,summary:focus-visible{outline:3px solid var(--rust);outline-offset:5px;border-radius:2px}img{display:block;max-width:100%;height:auto}h1,h2,h3,p,figure{margin:0}h1,h2,h3{line-height:1.2;letter-spacing:-.035em}h1{font-size:clamp(2.65rem,5.4vw,4.8rem);font-weight:650;max-width:16ch;text-wrap:balance}h2{font-size:clamp(1.65rem,2.6vw,2.5rem);font-weight:600}h3{font-size:1.25rem;font-weight:600}p+p{margin-top:1rem}.wrap{max-width:1200px;margin:auto;padding-inline:40px}.skip{position:fixed;top:10px;left:10px;padding:10px 18px;background:var(--ink);color:white;z-index:10;transform:translateY(-150%)}.skip:focus{transform:none}.top{display:flex;align-items:center;justify-content:space-between;gap:24px;min-height:100px;border-bottom:1px solid var(--line)}.brand{display:flex;gap:12px;align-items:center;text-decoration:none;color:var(--ink);font-size:21px;font-weight:650;letter-spacing:-.04em}.brand img{width:38px;height:38px;border-radius:10px}.nav{display:flex;align-items:center;gap:26px;flex-wrap:wrap;font-size:14px}.nav a{color:var(--ink);text-decoration:none}.nav a[aria-current=page]{color:var(--rust);text-decoration:underline}.nav .language{padding-left:22px;border-left:1px solid var(--line)}.eyebrow{text-transform:uppercase;letter-spacing:.17em;font-size:11px;font-weight:700;color:var(--rust);margin-bottom:24px}.hero{display:grid;grid-template-columns:1fr 1.12fr;gap:58px;align-items:center;padding-block:86px 80px}.hero .lead{margin-top:28px;max-width:43ch;color:var(--muted);font-size:19px}.actions{display:flex;flex-wrap:wrap;gap:12px;margin-top:30px;align-items:center}.button{display:inline-flex;align-items:center;justify-content:center;gap:10px;padding:12px 22px;min-height:48px;background:var(--rust);color:white;text-decoration:none;border:1px solid var(--rust);border-radius:5px;font-weight:600;font-size:15px}.button.secondary{background:transparent;color:var(--ink);border-color:var(--line)}.micro{font-size:12px;color:var(--muted);margin-top:16px}.hero-visual{background:var(--soft);padding:28px 20px 20px;border-radius:9px;border:1px solid var(--line)}.hero-visual img{border-radius:5px;box-shadow:0 15px 40px #24252312}.hero-visual figcaption{font-size:12px;color:var(--muted);margin-top:18px;display:flex;justify-content:space-between;gap:12px}.section{padding-block:62px;border-top:1px solid var(--line)}.section-intro{display:grid;grid-template-columns:1fr 1fr;gap:60px;margin-bottom:36px}.section-intro p{color:var(--muted);max-width:49ch}.features{display:grid;grid-template-columns:repeat(3,1fr);gap:38px}.feature .number{font-size:12px;letter-spacing:.15em;color:var(--rust);margin-bottom:18px}.feature p{font-size:15px;color:var(--muted);margin-top:15px}.rule{display:grid;grid-template-columns:repeat(3,1fr);margin-block:36px;border-top:1px solid var(--line);border-bottom:1px solid var(--line)}.rule div{padding:27px 20px 27px 0}.rule strong{display:block;font-size:clamp(2.5rem,5vw,4rem);font-weight:500;line-height:1.1;letter-spacing:-.05em}.rule span{font-size:14px;color:var(--muted)}.page-head{padding-block:64px 42px;max-width:850px}.page-head h1{font-size:clamp(2.5rem,4.4vw,3.7rem);max-width:22ch}.page-head .lead{margin-top:24px;color:var(--muted);font-size:19px;max-width:62ch}.crumbs{font-size:12px;color:var(--muted);margin-bottom:28px}.crumbs a{color:var(--muted)}.downloads{display:grid;grid-template-columns:1fr 1fr;gap:26px;margin-bottom:55px}.platform{padding:30px;border:1px solid var(--line);border-radius:6px;background:#FFFFFF50}.platform .version{font-size:12px;color:var(--rust);letter-spacing:.08em;margin-bottom:14px}.platform h2{font-size:28px}.platform p{font-size:15px;color:var(--muted);margin-top:17px}.platform ul{padding-left:21px;font-size:14px}.platform .actions{margin-top:24px}.platform .button{font-size:14px;padding-inline:17px}.notice{padding:24px 28px;background:var(--soft);border-left:3px solid var(--rust);margin-block:26px}.notice h2,.notice h3{font-size:19px;margin-bottom:12px}.notice p{font-size:15px}.prose{max-width:780px;padding-bottom:65px}.prose h2{font-size:26px;margin-block:38px 18px}.prose h3{margin-block:28px 12px}.prose li{padding-left:4px;margin-block:8px}.prose p,.prose li{color:#484A43}.faq-list{border-top:1px solid var(--line);margin-top:14px}.faq-list details{border-bottom:1px solid var(--line);padding-block:21px}.faq-list summary{cursor:pointer;list-style-position:outside;margin-left:20px;font-weight:600;font-size:18px;padding-left:5px}.faq-list details p{font-size:16px;margin:17px 0 0 25px}.gallery{display:grid;grid-template-columns:1fr 1fr;gap:28px}.gallery figure{padding:18px;background:var(--soft);border:1px solid var(--line);border-radius:6px}.gallery img{border-radius:4px}.gallery figcaption{font-size:13px;color:var(--muted);margin-top:14px}.endnote{display:flex;align-items:center;justify-content:space-between;gap:30px}.endnote p{font-size:16px;color:var(--muted);margin-top:14px}.footer{border-top:1px solid var(--line);padding-block:35px 40px;display:flex;gap:25px;justify-content:space-between;align-items:start;color:var(--muted);font-size:12px}.footer nav{display:flex;gap:18px;flex-wrap:wrap}.footer a{color:var(--muted)}.sources{font-size:14px}.pill{font-size:11px;border:1px solid var(--line);padding:4px 8px;border-radius:3px;color:var(--muted)}
@media(max-width:900px){.wrap{padding-inline:25px}.top{align-items:flex-start;padding-block:25px;gap:20px}.nav{gap:15px;justify-content:flex-end;max-width:380px}.hero{grid-template-columns:1fr;gap:42px;padding-block:55px}.hero h1{max-width:18ch}.hero .lead{max-width:52ch}.hero-visual{max-width:750px}.section-intro{gap:35px}.features{gap:24px}.downloads{gap:18px}.platform{padding:23px}.page-head{padding-top:45px}}
@media(max-width:600px){body{font-size:16px}.wrap{padding-inline:20px}.top{display:block}.brand{font-size:20px}.brand img{width:32px;height:32px}.nav{justify-content:flex-start;max-width:none;gap:12px 18px;margin-top:23px;font-size:13px}.nav .language{padding-left:15px}.hero{padding-block:45px;gap:33px}.hero h1{font-size:42px;max-width:16ch}.hero .lead,.page-head .lead{font-size:17px}.hero-visual{padding:15px 12px}.hero-visual figcaption{font-size:10px}.section{padding-block:40px}.section-intro,.features,.downloads,.gallery{grid-template-columns:1fr;gap:28px}.section-intro{margin-bottom:28px}.feature{border-top:1px solid var(--line);padding-top:23px}.feature .number{margin-bottom:12px}.rule div{padding-right:8px}.rule strong{font-size:42px}.rule span{font-size:12px}.page-head h1{font-size:37px}.endnote,.footer{display:block}.footer nav{margin-top:20px}.notice{padding:20px}.actions .button{flex-grow:1}.page-head{padding-bottom:30px}.prose h2{font-size:24px}}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
'''

CONTENT = {
'zh': {
    'name': '歇会儿 Breather', 'nav': ['首页', '下载', '常见问题', '隐私', '20-20-20'],
    'titles': ['歇会儿 Breather｜Mac 与 Windows 眼睛休息提醒', '免费下载歇会儿｜Mac 与 Windows 版本 · Breather', '歇会儿常见问题｜用眼时长、休息提醒与平台支持', '隐私与数据说明｜歇会儿 Breather', '20-20-20 法则指南｜给屏幕工作留一点间隔 · Breather'],
    'descriptions': ['歇会儿 Breather 是免费的 Mac 与 Windows 眼睛休息提醒工具。估算电脑使用时长，安排休息节奏，本地保存设置与记录，无订阅。', '下载歇会儿 Breather：macOS 13+ Apple Silicon 原生版与 Windows x64 Electron 版。查看实际版本、安装要求、未签名提示与官方下载链接。', '了解歇会儿的用眼时长估算、空闲判断、免费使用、平台支持和产品边界。没有 iPhone 应用或云端自动同步，不测量真实视线或医学疲劳。', '歇会儿的设置与统计保存在本机。了解 macOS 可选权限、Windows 数据、备份，以及 GitHub 网站与下载服务可能产生的访问日志。', '20-20-20 是一种屏幕休息习惯：每 20 分钟，看向约 20 英尺远处，持续 20 秒。了解一般建议、提醒工具的边界与权威参考资料。'],
},
'en': {
    'name': 'Breather', 'nav': ['Home', 'Download', 'FAQ', 'Privacy', '20-20-20'],
    'titles': ['Breather — Free eye break reminder for Mac and Windows', 'Download Breather — Free macOS and Windows eye break reminder', 'Breather FAQ — Activity estimates, eye breaks and supported devices', 'Breather privacy — Local data, permissions and website hosting', 'The 20-20-20 rule — A practical screen-break guide | Breather'],
    'descriptions': ['Breather is a free eye break reminder for Mac and Windows. Estimate computer-use time, plan regular breaks and keep settings and records locally. No subscriptions.', 'Download Breather for Apple Silicon on macOS 13+ or Windows x64. Compare native Mac and Electron Windows releases, requirements and unsigned installation notices.', 'Answers about Breather activity estimates, idle detection, free downloads and platform limits. No iPhone app or cloud autosync; no gaze tracking or medical fatigue measurement.', 'How Breather stores local settings and records, what optional macOS permissions do, and how GitHub hosting and downloads may generate access logs.', 'A concise 20-20-20 guide: every 20 minutes, look about 20 feet away for 20 seconds. Read general screen-break advice, product limits and professional references.'],
}}


def paragraph(text):
    return '<p>' + text + '</p>'


def build(config, output):
    """Render into output without deleting files or touching supplied PNG assets."""
    output = Path(output)
    base = config['siteUrl'].rstrip('/') + '/'
    if urlsplit(base).scheme != 'https' or not urlsplit(base).netloc:
        raise ValueError('siteUrl must be an absolute HTTPS URL')
    repo = config['repositoryUrl'].rstrip('/')
    if urlsplit(repo).scheme != 'https' or not urlsplit(repo).netloc:
        raise ValueError('repositoryUrl must be an absolute HTTPS URL')
    mac, win = config['macVersion'], config['windowsVersion']
    root_path = urlsplit(base).path
    downloads = {
        'mac': f'{repo}/releases/download/v{mac}/Breather-macOS-{mac}.zip',
        'setup': f'{repo}/releases/download/v{win}/Breather-{win}-x64-setup.exe',
        'portable': f'{repo}/releases/download/v{win}/Breather-{win}-x64-portable.exe',
    }

    def write(relative, text):
        path = output / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')

    def local(path):
        return escape(root_path + path, quote=True)

    def link(path, text, css=''):
        return f'<a href="{local(path)}"' + (f' class="{css}"' if css else '') + f'>{text}</a>'

    def external(url, text, css=''):
        return f'<a href="{escape(url, quote=True)}"' + (f' class="{css}"' if css else '') + f'>{text}</a>'

    def screenshot(file, alt, label):
        width, height = (1180, 900) if file == 'mac-dashboard.png' else (1008, 655)
        return f'<figure><img src="{local("assets/" + file)}" alt="{alt}" loading="lazy" width="{width}" height="{height}"><figcaption>{label}</figcaption></figure>'

    for language in ['zh', 'en']:
        zh = language == 'zh'
        c = CONTENT[language]
        prefix = '' if zh else 'en/'
        T = lambda chinese, english: chinese if zh else english
        for index, route in enumerate(ROUTES):
            current = prefix + route
            title, description = c['titles'][index], c['descriptions'][index]
            canonical = base + current
            nav = ''.join(f'<a href="{local(prefix + r)}"' + (' aria-current="page"' if r == route else '') + f'>{label}</a>' for r, label in zip(ROUTES, c['nav']))
            alternate_prefix = 'en/' if zh else ''
            nav += f'<a class="language" lang="{T("en", "zh-CN")}" hreflang="{T("en", "zh-CN")}" href="{local(alternate_prefix + route)}">{T("EN", "中文")}</a>'
            breadcrumb = [{'@type': 'ListItem', 'position': 1, 'name': c['nav'][0], 'item': base + prefix}]
            if route:
                breadcrumb.append({'@type': 'ListItem', 'position': 2, 'name': c['nav'][index], 'item': canonical})
            graph = [
                {'@type': 'WebSite', '@id': base + '#website', 'url': base, 'name': 'Breather', 'inLanguage': ['zh-CN', 'en']},
                {'@type': 'WebPage', '@id': canonical + '#page', 'url': canonical, 'name': title, 'description': description, 'inLanguage': T('zh-CN', 'en'), 'isPartOf': {'@id': base + '#website'}},
                {'@type': 'BreadcrumbList', 'itemListElement': breadcrumb},
            ]
            for system, version, key, requirements in [('macOS', mac, 'mac', 'macOS 13 or later; Apple Silicon'), ('Windows', win, 'setup', 'Windows x64; Electron 45.3.0')]:
                graph.append({'@type': 'SoftwareApplication', '@id': base + '#' + system.lower(), 'name': 'Breather for ' + system, 'url': base + prefix + 'download/', 'applicationCategory': 'UtilitiesApplication', 'operatingSystem': system, 'softwareVersion': version, 'softwareRequirements': requirements, 'downloadUrl': downloads[key], 'isAccessibleForFree': True, 'offers': {'@type': 'Offer', 'price': '0', 'priceCurrency': 'USD', 'url': base + prefix + 'download/'}, 'description': T('免费桌面休息提醒工具；非医疗设备，不测量真实视线或医学疲劳。', 'Free desktop break reminder; not a medical device and does not measure actual gaze or medical fatigue.'), 'image': base + 'assets/' + ('mac-dashboard.png' if system == 'macOS' else 'windows-dashboard.png')})
            schema = json.dumps({'@context': 'https://schema.org', '@graph': graph}, ensure_ascii=False).replace('<', '\\u003c')
            crumb = f'<div class="crumbs">{link(prefix, c["nav"][0])} <span aria-hidden="true"> / </span> {c["nav"][index]}</div>' if route else ''

            if index == 0:
                body = f'''<section class="hero"><div><p class="eyebrow">{T('给专注留一点空隙', 'A little space between focus')}</p><h1>{T('认真工作，<br>也记得歇会儿。', 'Stay focused.<br>Remember to<br>take a breather.')}</h1><p class="lead">{T('本地的眼睛休息提醒，让长时间的屏幕工作有一个停顿。看看用眼时长，安排自己的休息节奏。', 'A quiet eye break reminder for long days at a screen. See your estimated computer-use time and make room for regular breaks.')}</p><div class="actions">{link(prefix + 'download/', T('免费下载', 'Download free') + ' <span aria-hidden="true">↗</span>', 'button')}{link(prefix + 'guidance/20-20-20/', T('了解 20-20-20', 'Explore 20-20-20'), 'button secondary')}</div><p class="micro">{T('Mac · Windows x64　/　免费，无订阅', 'Mac · Windows x64　/　Free. No subscriptions.')}</p></div><figure class="hero-visual"><img src="{local('assets/mac-dashboard.png')}" alt="{T('歇会儿 macOS 原生版仪表盘，显示使用统计和休息控制', 'Breather native macOS dashboard showing activity estimates and break controls')}" width="1180" height="900" fetchpriority="high"><figcaption><span>{T('演示数据 · 非真实使用记录', 'Demo data · Not actual usage records')}</span><span>macOS · v{mac}</span></figcaption></figure></section>
<section class="section"><div class="section-intro"><h2>{T('不是多做一点，<br>是适时停一下。', 'Not more to do.<br>A moment to step away.')}</h2><p>{T('歇会儿把电脑活动信号转成易读的时间记录。它是习惯工具，不是视线追踪器，也不把统计数字当成医学判断。', 'Breather turns computer activity signals into readable time estimates. It is a habit tool, not a gaze tracker, and its numbers are not a medical assessment.')}</p></div><div class="features">'''
                features = [
                    (T('看见使用节奏', 'See your rhythm'), T('查看估算的用眼时长与本地历史记录。空闲和活动信号只是近似，不代表你始终注视屏幕。', 'Review estimated computer-use time and local history. Idle and activity signals are approximations, not proof that you are looking at the screen.')),
                    (T('给休息留个位置', 'Make space for breaks'), T('按自己的工作节奏设置休息间隔和时长。提醒出现时，给远处的事物一点注意力。', 'Set break intervals and duration around your work. When a reminder arrives, give something farther away a little attention.')),
                    (T('数据留在本机', 'Keep it local'), T('设置和记录保存在电脑上，支持手动导出备份。没有账号体系，也没有云端自动同步。', 'Settings and records stay on your computer, with manual backup export. There is no account system or automatic cloud sync.')),
                ]
                body += ''.join(f'<article class="feature"><p class="number">0{n}</p><h3>{heading}</h3><p>{text}</p></article>' for n, (heading, text) in enumerate(features, 1)) + '</div></section>'
                body += f'''<section class="section"><div class="section-intro"><h2>{T('给目光，<br>换一个距离。', 'Give your eyes<br>a different distance.')}</h2><p>{T('20-20-20 是一种简单的屏幕休息习惯：每 20 分钟，看向约 20 英尺（约 6 米）以外，持续 20 秒。先从记得停下来开始。', 'The 20-20-20 rule is a simple screen-break habit: every 20 minutes, look about 20 feet (6 metres) away for 20 seconds. Start by remembering to pause.')}</p></div>{rule(zh)}{link(prefix + 'guidance/20-20-20/', T('阅读指南与参考资料 →', 'Read the guide and references →'))}</section>
<section class="section"><div class="section-intro"><h2>{T('两种桌面，<br>同一个休息提醒。', 'Two desktops.<br>One reminder to pause.')}</h2><p>{T('macOS 是 Apple Silicon 原生应用；Windows 是 x64 Electron 应用。版本、系统要求和安装方式不同，请按平台选择。', 'macOS uses a native Apple Silicon app; Windows uses an x64 Electron app. Versions, system requirements and installation steps differ.')}</p></div><div class="gallery">{screenshot('mac-dashboard.png', T('歇会儿 macOS 仪表盘截图', 'Breather macOS dashboard screenshot'), f'macOS · {mac} · Apple Silicon · ' + T('演示数据', 'Demo data'))}{screenshot('windows-dashboard.png', T('歇会儿 Windows 仪表盘截图', 'Breather Windows dashboard screenshot'), f'Windows x64 · {win} · Electron 45.3.0 · ' + T('演示 / 空白测试数据', 'Demo / blank test data'))}</div></section>
<section class="section endnote"><div><h2>{T('下一次专注之前，先留好间隔。', 'A little breathing room for your next session.')}</h2><p>{T('免费使用，无订阅。先了解系统要求与未签名安装说明。', 'Free to use, without subscriptions. Check requirements and unsigned installation notes first.')}</p></div>{link(prefix + 'download/', T('选择你的版本', 'Choose your version'), 'button')}</section>'''
            elif index == 1:
                body = page_head(crumb, T('下载歇会儿', 'Download Breather'), T('选对平台，再开始。两个版本均可免费下载，无订阅。', 'Choose your platform and take it from there. Both versions are free, with no subscriptions.'), T('一个提醒，两种桌面', 'One reminder. Two desktops.'))
                body += f'''<div class="downloads"><section class="platform"><p class="version">NATIVE · v{mac}</p><h2>macOS</h2><p>{T('Apple Silicon Mac · macOS 13 或更高版本。不是 Intel 安装包。', 'Apple Silicon Mac · macOS 13 or later. Not an Intel build.')}</p><ul><li>{T('原生 Swift / SwiftUI 应用', 'Native Swift / SwiftUI application')}</li><li>{T('ZIP 解压后移入「应用程序」', 'Unzip and move the app to Applications')}</li><li>{T('未签名 / 未公证，可能触发 Gatekeeper 警告', 'Unsigned and not notarized; Gatekeeper may warn')}</li></ul><div class="actions">{external(downloads['mac'], T('下载 macOS ZIP', 'Download macOS ZIP'), 'button')}</div></section><section class="platform"><p class="version">ELECTRON 45.3.0 · v{win}</p><h2>Windows x64</h2><p>{T('适用于 x64 Windows；不是 ARM64 原生版，也不提供 32 位版本。', 'For x64 Windows. Not a native ARM64 build; no 32-bit package is provided.')}</p><ul><li>{T('Electron 桌面应用', 'Electron desktop application')}</li><li>{T('安装版和便携版可选', 'Choose installer or portable executable')}</li><li>{T('未签名，可能触发 SmartScreen 警告', 'Unsigned; SmartScreen may warn')}</li></ul><div class="actions">{external(downloads['setup'], T('下载安装版', 'Download installer'), 'button')}{external(downloads['portable'], T('下载便携版', 'Download portable'), 'button secondary')}</div></section></div>
<div class="prose"><aside class="notice"><h2>{T('安装前，请知道', 'Before you install')}</h2><p>{T('当前发布文件未进行开发者签名。系统警告不等于已经验证安全；只从本页链接的官方 GitHub Releases 获取文件，核对版本。若不确定来源或不愿运行未签名软件，请不要绕过系统保护。', 'Current release files are not developer-signed. A system warning is not a safety verification. Obtain files only from the official GitHub Releases linked here and check the version. If you cannot verify the source or do not want unsigned software, do not bypass system protection.')}</p></aside><h2>{T('如何安装', 'Installation at a glance')}</h2><ol><li>{T('macOS：下载 ZIP 并解压，将歇会儿移到「应用程序」。若系统阻止打开，请先核实来源，再按 macOS「隐私与安全性」中的提示操作；无需关闭 Gatekeeper。', 'macOS: download and unzip the archive, then move Breather to Applications. If macOS blocks it, verify the source first and follow the relevant Privacy & Security prompt; do not disable Gatekeeper.')}</li><li>{T('Windows：运行安装版，或把便携版放在自己管理的位置后运行。便携版不代表没有本地数据；请查看隐私说明。', 'Windows: run the installer, or keep the portable executable in a location you manage. Portable does not mean no local data is stored; see the privacy page.')}</li><li>{T('首次打开后设置提醒节奏。macOS 的增强输入和屏幕活动检测是可选功能，权限按需开启。', 'On first launch, choose a reminder rhythm. Enhanced input and screen activity detection on macOS are optional and permissions can be enabled as needed.')}</li></ol><h2>{T('版本与支持范围', 'Versions and scope')}</h2><p>{T(f'macOS 当前版本为 {mac}，Windows 当前版本为 {win}。没有 iPhone 应用，不提供云端自动同步。免费分发不等于授予开源许可证；本页面不作开源授权声明。', f'The current macOS version is {mac}; the current Windows version is {win}. There is no iPhone app or cloud autosync. Free distribution does not itself grant an open-source license; this page makes no open-source licensing claim.')}</p><p>{external(repo + '/releases', T('所有官方发布与版本说明 ↗', 'Official releases and release notes ↗'))} · {link(prefix + 'privacy/', T('隐私与本地数据', 'Privacy and local data'))}</p></div>'''
            elif index == 2:
                body = page_head(crumb, T('先了解，再歇会儿。', 'A few things worth knowing.'), T('关于用眼时长、提醒、支持平台和产品边界的直接回答。', 'Straight answers about time estimates, reminders, platforms and product limits.'), T('常见问题', 'Frequently asked questions'))
                questions = [
                    (T('歇会儿是什么？', 'What is Breather?'), T('歇会儿 Breather 是桌面眼睛休息提醒工具，用电脑活动信号估算使用时长，并按设置提醒休息。它不是医疗设备，不诊断或治疗眼部疾病。', 'Breather is a desktop eye break reminder. It estimates use from computer activity signals and reminds you to pause on your chosen schedule. It is not a medical device and does not diagnose or treat eye conditions.')),
                    (T('用眼时长等于真实注视屏幕的时间吗？', 'Does computer-use time measure actual gaze?'), T('不等于。空闲检测只能提供电脑活动的近似信号，不能证明人在电脑前或正在看屏幕。静静阅读、播放视频、后台动画等场景可能与实际用眼不同；可选增强检测也不改变这一边界。', 'No. Idle detection only supplies approximate computer activity signals; it cannot prove human presence or gaze. Quiet reading, video playback and background animation can differ from actual screen viewing. Optional enhanced detection does not remove this limit.')),
                    (T('应用里的疲劳数值有医学意义吗？', 'Is the fatigue indicator a medical measurement?'), T('没有。界面中的疲劳值是由使用与休息时长计算的提醒模型，不是对眼睛疲劳、视力或健康状态的测量，也没有经过临床验证。不要据此判断是否需要就医。', 'No. The fatigue indicator is a reminder model calculated from work and break durations, not a measurement of eye strain, eyesight or health. It is not clinically validated and should not guide decisions about seeking care.')),
                    (T('支持哪些设备？有 iPhone 应用吗？', 'Which devices are supported? Is there an iPhone app?'), T(f'macOS {mac} 支持 Apple Silicon 和 macOS 13+；Windows {win} 为 x64 Electron 45.3.0 应用。没有 iPhone 应用、Intel Mac 发布包或 Windows ARM64 原生包。', f'macOS {mac} supports Apple Silicon on macOS 13+. Windows {win} is an x64 Electron 45.3.0 app. There is no iPhone app, Intel Mac release package or native Windows ARM64 package.')),
                    (T('免费吗？需要订阅或账号吗？', 'Is it free? Do I need a subscription or account?'), T('当前桌面版本免费下载，无订阅，不需要应用账号。免费使用不代表仓库附带开源许可证。', 'The current desktop releases are free to download, with no subscription or app account required. Free use does not mean the repository carries an open-source license.')),
                    (T('Mac 和 Windows 的记录会自动同步吗？', 'Will my Mac and Windows records sync automatically?'), T('不会。设置与记录保存在本机，没有云端自动同步。可手动导出备份；不同平台与版本的备份格式不应假定可以互换，恢复前请保留原始数据。', 'No. Settings and records are local, with no cloud autosync. You can export backups manually. Do not assume backup formats are interchangeable across platforms or versions; keep original data before restoring.')),
                    (T('需要哪些权限？会记录键盘内容吗？', 'Which permissions are used? Are typed keys recorded?'), T('macOS 可选的增强输入检测使用辅助功能权限，只取活动时间，不保留按键文字；可选屏幕活动检测需要屏幕录制权限，在内存中比较低分辨率灰度网格，不保存屏幕图像。Windows 版使用系统空闲时长，不提供相同的 macOS 增强检测。', 'Optional macOS enhanced input detection uses Accessibility permission and activity timestamps, not retained key text. Optional screen activity detection requires Screen Recording permission and compares low-resolution grayscale grids in memory without saving screen images. Windows uses system idle time and does not provide the same macOS enhanced detection.')),
                    (T('为什么下载后会出现安全提示？', 'Why does my system show a security warning?'), T('当前发布包未签名，macOS 也未公证，因此 Gatekeeper 或 SmartScreen 可能提示。请核实官方来源；不确定时不要绕过系统保护。', 'Current packages are unsigned and the Mac app is not notarized, so Gatekeeper or SmartScreen may warn. Verify the official source and do not bypass protections when uncertain.')),
                    (T('20-20-20 能保证缓解不适吗？', 'Does 20-20-20 guarantee relief?'), T('不能保证。它是一般性的屏幕休息建议，歇会儿没有证明任何医疗效果。持续眼痛、视物模糊或其他不适应咨询眼科或视光专业人士。', 'No. It is general screen-break guidance, and Breather makes no claim of proven medical benefit. Persistent eye pain, blurred vision or other symptoms deserve advice from an eye-care professional.')),
                ]
                body += '<div class="prose"><div class="faq-list">' + ''.join(f'<details><summary>{q}</summary><p>{a}</p></details>' for q, a in questions) + f'</div><p class="micro">{link(prefix + "download/", T("查看下载与系统要求 →", "See downloads and requirements →"))}　{link(prefix + "privacy/", T("阅读隐私说明 →", "Read privacy details →"))}</p></div>'
            elif index == 3:
                body = page_head(crumb, T('数据在本机，<br>边界说清楚。', 'Local data.<br>Clear boundaries.'), T('应用数据、可选权限与网站托管分开说明。无需账号，也没有云端自动同步。', 'App data, optional permissions and website hosting are separate. No account or automatic cloud sync.'), T('隐私与数据', 'Privacy & data'))
                sections = [
                    (T('设置与记录保存在电脑上', 'Settings and records stay on your computer'), T('桌面应用把设置、使用统计和休息记录保存到本机。Windows 版会在用户数据目录保存状态；macOS 版使用本地 Application Support 数据目录。卸载程序不一定删除这些数据，删除前请按需要导出备份。', 'The desktop app stores settings, use statistics and break records locally. Windows keeps state in a user-data directory; macOS uses a local Application Support directory. Uninstalling an app may not remove this data. Export a backup first if you want to keep it.')),
                    (T('不依赖账号或云端同步', 'No account or cloud autosync'), T('当前桌面版本没有应用账号体系，不把统计记录自动同步到云端。CSV 导出和 JSON 备份由你手动操作，文件可能包含个人使用习惯；你选择的保存位置、云盘或分享渠道可能让文件离开本机。', 'The current desktop releases have no app account system and do not automatically sync statistics to a cloud service. CSV exports and JSON backups are manual and may reveal personal usage patterns. A destination you choose, such as a cloud drive or sharing service, may take those files off your computer.')),
                    (T('macOS 可选权限', 'Optional macOS permissions'), T('增强输入检测是可选的，使用辅助功能权限获取活动时间戳，不记录按键内容、指针位置或目标应用。屏幕活动检测也是可选的，需要屏幕录制权限：屏幕帧在本机内存中转为低分辨率灰度网格来比较变化，不保存截图或视频。屏幕权限仍属于敏感权限；不愿授权时可保持关闭，并可在系统设置中撤回。', 'Enhanced input detection is optional and uses Accessibility permission for activity timestamps, without recording key text, pointer positions or target apps. Screen activity detection is also optional and needs Screen Recording permission: screen frames are reduced to low-resolution grayscale grids in local memory to compare changes; screenshots and video are not saved. Screen permission is still sensitive. Leave it off if you prefer and revoke permissions in System Settings at any time.')),
                    (T('Windows 的检测方式', 'Detection on Windows'), T('Windows Electron 版使用系统空闲时间估算活动，不提供 macOS 的辅助功能增强输入或屏幕活动检测。这些信号不能确认真实视线、人是否在场或身体疲劳程度。', 'The Windows Electron app estimates activity using system idle time. It does not provide the macOS Accessibility-based enhanced input or screen activity detection. These signals cannot confirm actual gaze, human presence or physical fatigue.')),
                    (T('本网站与 GitHub 下载服务', 'This website and GitHub downloads'), T('本站是静态页面，不加载第三方字体、分析脚本或广告，也不设置应用自己的追踪系统。页面由 GitHub Pages 托管，下载通过 GitHub Releases 提供；GitHub 可能处理 IP 地址、请求和访问日志等服务数据，其处理方式受 GitHub 隐私政策约束。本地应用数据的说明不代表托管服务不会记录访问。', 'This is a static website without remote fonts, analytics scripts, advertising or an app-operated tracking system. GitHub Pages hosts the site and GitHub Releases serves downloads. GitHub may process service data such as IP addresses, requests and access logs under its own privacy statement. The local-app data description does not mean the hosting service records no visits.')),
                    (T('反馈时，请少分享一点数据', 'Share less when reporting an issue'), T('若通过公开仓库反馈问题，请不要上传个人备份、原始统计、敏感截图或系统凭据。问题描述与附件会受相应平台的公开可见性和隐私规则影响。', 'When reporting an issue in the public repository, do not upload personal backups, raw records, sensitive screenshots or system credentials. Your report and attachments are subject to that platform’s visibility and privacy rules.')),
                ]
                body += '<div class="prose">' + ''.join(f'<h2>{h}</h2><p>{p}</p>' for h, p in sections) + f'<p>{external("https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement", T("GitHub 隐私声明 ↗", "GitHub General Privacy Statement ↗"))} · {external(repo, T("公开仓库 ↗", "Public repository ↗"))}</p></div>'
            else:
                body = page_head(crumb, T('20 分钟之后，<br>看一会儿远处。', 'After 20 minutes,<br>look a little farther.'), T('20-20-20 是一种容易记住的屏幕休息习惯，不是诊断、治疗或效果承诺。', '20-20-20 is an easy-to-remember screen-break habit, not a diagnosis, treatment or promise of results.'), T('20-20-20 指南', 'The 20-20-20 guide'))
                body += f'<div class="prose">{rule(zh)}<h2>{T("20-20-20 是什么意思？", "What does 20-20-20 mean?")}</h2><p>{T("美国视光协会（AOA）的一般建议是：每使用屏幕 20 分钟，花 20 秒看向 20 英尺（约 6 米）远的事物。它提供一个便于记忆的休息节奏，而不是对每个人都有效的精确处方。", "The American Optometric Association (AOA) describes a general habit: every 20 minutes of screen use, spend 20 seconds looking at something about 20 feet (6 metres) away. It is a memorable rhythm, not a precise prescription that works identically for everyone.")}</p><h2>{T("怎样把它放进工作日？", "How can I fit it into a workday?")}</h2><ol><li>{T("先找一个远处的目标，例如窗外的树或走廊尽头；不要只是换成看手机。", "Choose a distant point, such as a tree outside or the end of a hallway; do not simply switch to your phone.")}</li><li>{T("提醒出现后把注意力移开约 20 秒，自然眨眼，调整一下姿势。", "When a reminder arrives, look away for about 20 seconds, blink naturally and adjust your posture.")}</li><li>{T("结合环境调整：减少反光，保持舒适的屏幕距离，并留出更长的离屏休息。", "Also consider your environment: reduce glare, keep a comfortable screen distance and make room for longer breaks away from the screen.")}</li></ol><h2>{T("歇会儿能做什么，不能做什么？", "What can Breather do — and not do?")}</h2><p>{T("你可以把休息间隔和时长设置为适合自己的节奏，例如 20 分钟与 20 秒。应用提供提醒和电脑活动时长估算，不知道你是否真的看向远方，不测量眼睛疲劳，也没有证明能预防或治疗疾病。界面中的疲劳值只是提醒模型。", "You can set a break rhythm that suits you, such as a 20-minute interval and a 20-second break. The app provides reminders and computer activity estimates. It cannot know whether you actually looked into the distance, does not measure eye fatigue and has not demonstrated prevention or treatment of disease. Its fatigue indicator is only a reminder model.")}</p><aside class="notice"><h3>{T("不适持续时，别只依赖提醒", "Persistent symptoms need more than reminders")}</h3><p>{T("如果眼痛、视物模糊或其他不适持续，请咨询眼科或视光专业人士；突然或严重的视觉变化应及时就医。本页为一般教育信息，不替代专业诊疗建议。", "If eye pain, blurred vision or other symptoms persist, consult an eye-care professional. Sudden or severe changes in vision need prompt medical attention. This page is general educational information, not a substitute for professional advice.")}</p></aside><h2>{T("参考资料", "References")}</h2><ul class="sources"><li>{external(AOA, "American Optometric Association — Computer vision syndrome ↗")}<br>{T("20-20-20 与屏幕使用环境的一般建议；本页对规则的说明依据此来源。", "General advice on 20-20-20 and the screen-use environment; the rule description on this page follows this source.")}</li><li>{external(AAO, "American Academy of Ophthalmology — Computers, Digital Devices and Eye Strain ↗")}<br>{T("进一步阅读：数字设备与眼睛不适。与应用无合作或背书关系。", "Further reading on digital devices and eye strain. No partnership with or endorsement of the app is implied.")}</li></ul><p>{link(prefix + "download/", T("用歇会儿给休息加一个提醒 →", "Add a reminder with Breather →"))}</p></div>'

            alternates = ''.join(f'<link rel="alternate" hreflang="{code}" href="{escape(base + p + route, quote=True)}">' for code, p in [('zh-CN', ''), ('en', 'en/'), ('x-default', '')])
            image = base + 'assets/mac-dashboard.png'
            html = f'''<!doctype html>
<html lang="{T('zh-CN', 'en')}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>{escape(title)}</title><meta name="description" content="{escape(description, quote=True)}"><link rel="canonical" href="{escape(canonical, quote=True)}">{alternates}<meta property="og:type" content="website"><meta property="og:site_name" content="Breather"><meta property="og:locale" content="{T('zh_CN', 'en_US')}"><meta property="og:locale:alternate" content="{T('en_US', 'zh_CN')}"><meta property="og:title" content="{escape(title, quote=True)}"><meta property="og:description" content="{escape(description, quote=True)}"><meta property="og:url" content="{escape(canonical, quote=True)}"><meta property="og:image" content="{escape(image, quote=True)}"><meta property="og:image:alt" content="{T('歇会儿 macOS 仪表盘', 'Breather macOS dashboard')}"><meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="{escape(title, quote=True)}"><meta name="twitter:description" content="{escape(description, quote=True)}"><meta name="twitter:image" content="{escape(image, quote=True)}"><meta name="twitter:image:alt" content="{T('歇会儿 macOS 仪表盘', 'Breather macOS dashboard')}"><link rel="icon" type="image/png" href="{local('assets/logo.png')}"><link rel="stylesheet" href="{local('assets/style.css')}"><script type="application/ld+json">{schema}</script></head>
<body><a class="skip" href="#main">{T('跳至正文', 'Skip to content')}</a><div class="wrap"><header class="top"><a class="brand" href="{local(prefix)}"><img src="{local('assets/logo.png')}" width="38" height="38" alt="{T('歇会儿标志', 'Breather mark')}"><span>{c['name']}</span></a><nav class="nav" aria-label="{T('主导航', 'Main navigation')}">{nav}</nav></header><main id="main">{body}</main><footer class="footer"><div><strong>{c['name']}</strong><br>{T('认真工作，也记得歇会儿。', 'Stay focused. Remember to take a breather.')}<br>{T('非医疗设备 · 不测量真实视线或医学疲劳', 'Not a medical device · No gaze or medical fatigue measurement')}</div><nav aria-label="{T('页脚导航', 'Footer navigation')}">{link(prefix + 'privacy/', T('隐私', 'Privacy'))}{external(repo, 'GitHub ↗')}{link('facts.md', T('产品事实', 'Product facts'))}{link('llms.txt', 'llms.txt')}{link('sitemap.xml', 'Sitemap')}</nav></footer></div></body></html>
'''
            write(current + 'index.html', html)
    write('assets/style.css', CSS.strip() + '\n')
    urls = [base + p + r for p in ['', 'en/'] for r in ROUTES]
    sitemap = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(f'  <url><loc>{xml_escape(u)}</loc></url>\n' for u in urls) + '</urlset>\n'
    write('sitemap.xml', sitemap)
    facts = f'''# Breather / 歇会儿 — product facts

- Official website: {base}
- Public repository: {repo}
- Category: desktop eye break reminder / 桌面眼睛休息提醒.
- macOS: version {mac}; native Swift/SwiftUI; Apple Silicon; macOS 13 or later. No Intel release package.
- Windows: version {win}; x64; Electron 45.3.0. No native ARM64 or 32-bit package.
- Cost: current desktop binaries are free, no subscriptions, no app account required. Free distribution is not an open-source licensing grant; no license claim is made here.
- macOS download: {downloads['mac']}
- Windows installer: {downloads['setup']}
- Windows portable: {downloads['portable']}
- Current releases are unsigned; the Mac release is not notarized. Gatekeeper / SmartScreen warnings may occur. Verify origin; do not disable system protections.
- Function: estimate computer activity time, show local history, remind users to take breaks at configurable intervals/durations.
- Limits: idle/activity signals cannot prove human presence or actual gaze. Quiet reading, video and animation may differ from actual viewing.
- The fatigue indicator is a reminder model, not a medical measurement or clinically validated health assessment. No diagnosis, treatment, prevention or guaranteed benefit is claimed.
- No iPhone app. No automatic cloud sync. Do not assume backups are interchangeable between platforms or versions.
- Settings and records are saved locally; exports/backups are user-initiated. User-selected cloud storage or sharing may take exported files off-device.
- macOS optional enhanced input detection uses Accessibility permission for activity timestamps, not retained key text. Optional screen detection uses Screen Recording permission and low-resolution grayscale grids in local memory; screen images/video are not saved.
- Windows uses system idle time, not the macOS enhanced input/screen detection features.
- Website: static, no remote fonts/scripts/analytics operated by the app. GitHub Pages and GitHub Releases may process IP addresses, requests and access logs under GitHub's privacy statement.
- Educational 20-20-20 guidance: every 20 minutes, look about 20 feet (6 metres) away for 20 seconds. General advice, not a product efficacy claim. Persistent symptoms need professional advice.
- Educational source: {AOA}
- Further reading: {AAO}

## 中文摘要

歇会儿是免费的桌面眼睛休息提醒工具。用眼时长是电脑活动估算，不证明真实视线；疲劳值是提醒模型，不是医学测量。无订阅，无 iPhone 应用，无云端自动同步。设置与记录保存在本机；网站托管与下载服务可能产生访问日志。当前发布包未签名，macOS 版未公证。20-20-20 是一般性的休息建议，不是医疗效果承诺。
'''
    write('facts.md', facts)
    write('llms.txt', f'''# Breather / 歇会儿

> Free desktop eye break reminder for Apple Silicon macOS 13+ and Windows x64. Local records, no subscriptions. Activity estimates are not gaze detection or medical measurements.

Official website: {base}
Public repository: {repo}
Current macOS version: {mac}. Current Windows version: {win} (Electron 45.3.0).

## Canonical product information

- [Chinese home]({base}): 眼睛休息提醒、用眼时长估算与产品概览。
- [English home]({base}en/): Product overview and limits.
- [Downloads]({base}en/download/): Exact versions, requirements and unsigned installation warnings.
- [FAQ]({base}en/faq/): No iPhone app or cloud autosync; no actual gaze or medical fatigue measurement.
- [Privacy]({base}en/privacy/): Local data, optional macOS permissions and GitHub hosting logs.
- [20-20-20 guide]({base}en/guidance/20-20-20/): General educational advice with professional references, not medical efficacy claims.
- [Product facts]({base}facts.md): Concise cross-language facts and exact release links.
- [Sitemap]({base}sitemap.xml): All ten Chinese/English canonical pages.

No ratings, testimonials, open-source licensing or guaranteed medical benefits are asserted. Discovery files do not guarantee crawler use or search/AI visibility. Project-path robots.txt is informational, not an origin-root policy.
''')
    write('robots.txt', f'''# This project-path robots.txt is informational only.
# Robots rules are authoritative only at the origin's /robots.txt.
# This GitHub Pages project does not control that origin-root policy.
# Sitemap for discovery: {base}sitemap.xml
''')


def rule(zh):
    labels = ['每隔 20 分钟', '看向约 20 英尺远处', '持续约 20 秒'] if zh else ['Every 20 minutes', 'Look about 20 feet away', 'For about 20 seconds']
    return '<div class="rule">' + ''.join(f'<div><strong>20</strong><span>{label}</span></div>' for label in labels) + '</div>'


def page_head(crumb, heading, description, eyebrow):
    return f'<header class="page-head">{crumb}<p class="eyebrow">{eyebrow}</p><h1>{heading}</h1><p class="lead">{description}</p></header>'


if __name__ == '__main__':
    build(json.loads((ROOT / 'public-config.json').read_text(encoding='utf-8')), ROOT / 'site')
    print('Built 10 bilingual pages and discovery documents in site/. Supplied PNG assets unchanged.')
