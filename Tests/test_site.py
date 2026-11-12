"""Dependency-free contract tests for the published static site."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit, unquote
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'site'
ROUTES = ['', 'download/', 'faq/', 'privacy/', 'guidance/20-20-20/']


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.tags = []
        self.title = ''
        self.headings = []
        self.jsonld = []
        self._title = False
        self._json = None
        self._h1 = False
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        self.tags.append((tag, attrs))
        self._title = tag == 'title' or self._title
        self._h1 = tag == 'h1' or self._h1
        if tag == 'script' and attrs.get('type') == 'application/ld+json':
            self._json = ''

    def handle_endtag(self, tag):
        if tag == 'title': self._title = False
        if tag == 'h1': self._h1 = False
        if tag == 'script' and self._json is not None:
            self.jsonld.append(json.loads(self._json))
            self._json = None

    def handle_data(self, data):
        if self._title: self.title += data
        if self._h1: self.headings.append(data)
        if self._json is not None: self._json += data

    def meta(self, key):
        return [a.get('content') for t, a in self.tags if t == 'meta' and (a.get('name') == key or a.get('property') == key)]

    def links(self, rel):
        return [a for t, a in self.tags if t == 'link' and a.get('rel') == rel]


class SiteContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = json.loads((ROOT / 'public-config.json').read_text())
        cls.base = cls.config['siteUrl']
        cls.pages = {prefix + route: Page((SITE / (prefix + route) / 'index.html').read_text())
                     for prefix in ['', 'en/'] for route in ROUTES
                     if (SITE / (prefix + route) / 'index.html').exists()}

    def test_generator_exists(self):
        self.assertTrue((ROOT / 'tools/build_site.py').is_file(), 'Static generator is not implemented')

    def test_ten_crawlable_pages(self):
        self.assertEqual(set(self.pages), {p + r for p in ['', 'en/'] for r in ROUTES})
        for route, page in self.pages.items():
            with self.subTest(route=route):
                self.assertTrue(page.headings)
                self.assertEqual(len([t for t, a in page.tags if t == 'h1']), 1)
                self.assertTrue(page.meta('viewport'))
                self.assertTrue(any(t == 'main' and a.get('id') == 'main' for t, a in page.tags))

    def test_unique_titles_descriptions_and_social_metadata(self):
        self.assertEqual(len({p.title for p in self.pages.values()}), 10)
        self.assertEqual(len({tuple(p.meta('description')) for p in self.pages.values()}), 10)
        for route, page in self.pages.items():
            with self.subTest(route=route):
                self.assertEqual(page.meta('og:url'), [self.base + route])
                self.assertEqual(page.meta('og:title'), [page.title])
                self.assertEqual(page.meta('twitter:card'), ['summary_large_image'])
                self.assertTrue(page.meta('og:image')[0].startswith(self.base))

    def test_canonical_and_reciprocal_hreflang(self):
        for route, page in self.pages.items():
            with self.subTest(route=route):
                self.assertEqual([a['href'] for a in page.links('canonical')], [self.base + route])
                bare = route.removeprefix('en/')
                expected = {'zh-CN': self.base + bare, 'en': self.base + 'en/' + bare, 'x-default': self.base + bare}
                actual = {a['hreflang']: a['href'] for a in page.links('alternate')}
                self.assertEqual(actual, expected)
                for language, target in actual.items():
                    other = self.pages[target.removeprefix(self.base)]
                    self.assertEqual({a['hreflang']: a['href'] for a in other.links('alternate')}, expected)

    def test_all_local_links_images_and_fragments_resolve(self):
        origin = urlsplit(self.base)
        for route, page in self.pages.items():
            for tag, attrs in page.tags:
                for key in ['href', 'src']:
                    raw = attrs.get(key)
                    if not raw: continue
                    url = urlsplit(urljoin(self.base + route, raw))
                    if url.netloc != origin.netloc: continue
                    with self.subTest(route=route, url=raw):
                        self.assertTrue(url.path.startswith(origin.path), 'Link lost project prefix')
                        relative = unquote(url.path[len(origin.path):])
                        target = SITE / relative
                        if url.path.endswith('/'): target /= 'index.html'
                        self.assertTrue(target.is_file(), str(target))
                        if url.fragment and target.suffix == '.html':
                            parsed = Page(target.read_text())
                            self.assertIn(url.fragment, [a.get('id') for t, a in parsed.tags])
                if tag == 'img': self.assertTrue(attrs.get('alt'))
                if tag == 'script': self.assertNotIn('src', attrs)
                if tag == 'link' and attrs.get('rel') == 'stylesheet':
                    self.assertFalse(attrs['href'].startswith(('https:', '//')))

    def test_jsonld_accurate_products_breadcrumbs_and_free_offers(self):
        for route, page in self.pages.items():
            with self.subTest(route=route):
                self.assertEqual(len(page.jsonld), 1)
                graph = page.jsonld[0]['@graph']
                self.assertTrue(any(x['@type'] == 'WebSite' for x in graph))
                self.assertTrue(any(x['@type'] == 'BreadcrumbList' for x in graph))
                apps = [x for x in graph if x['@type'] == 'SoftwareApplication']
                self.assertEqual(len(apps), 2)
                expected = {'macOS': self.config['macVersion'], 'Windows': self.config['windowsVersion']}
                for app in apps:
                    self.assertEqual(app['softwareVersion'], expected[app['operatingSystem']])
                    self.assertEqual(app['offers']['price'], '0')
                    self.assertEqual(app['offers']['priceCurrency'], 'USD')
                    self.assertTrue(app['downloadUrl'].startswith(self.config['repositoryUrl'] + '/releases/download/'))
                packed = json.dumps(graph)
                for forbidden in ['aggregateRating', 'ratingValue', 'review', 'license', 'medicalSpecialty']:
                    self.assertNotIn('"' + forbidden + '"', packed)

    def test_downloads_match_release_artifacts(self):
        repo = self.config['repositoryUrl']
        mac, win = self.config['macVersion'], self.config['windowsVersion']
        expected = [f'{repo}/releases/download/v{mac}/Breather-macOS-{mac}.zip',
                    f'{repo}/releases/download/v{win}/Breather-{win}-x64-setup.exe',
                    f'{repo}/releases/download/v{win}/Breather-{win}-x64-portable.exe']
        for route in ['download/', 'en/download/']:
            self.assertIn(route, self.pages)
            links = [a.get('href') for t, a in self.pages[route].tags if t == 'a']
            for url in expected: self.assertIn(url, links)

    def test_discovery_documents_and_robots_limitation(self):
        for name in ['sitemap.xml', 'llms.txt', 'facts.md', 'robots.txt', 'BUILD.md']:
            self.assertTrue((SITE / name).is_file(), name)
        sitemap = ET.parse(SITE / 'sitemap.xml')
        urls = [x.text for x in sitemap.findall('.//{http://www.sitemaps.org/schemas/sitemap/0.9}loc')]
        self.assertEqual(set(urls), {self.base + p + r for p in ['', 'en/'] for r in ROUTES})
        for name in ['llms.txt', 'facts.md']:
            text = (SITE / name).read_text()
            self.assertIn(self.config['repositoryUrl'], text)
            self.assertIn(self.base, text)
            self.assertIn(self.config['macVersion'], text)
            self.assertIn(self.config['windowsVersion'], text)
        self.assertIn('informational', (SITE / 'robots.txt').read_text())
        self.assertIn('origin', (SITE / 'BUILD.md').read_text())

    def test_guide_and_privacy_are_candid(self):
        for prefix in ['', 'en/']:
            guide = (SITE / prefix / 'guidance/20-20-20/index.html')
            self.assertTrue(guide.is_file())
            self.assertIn('https://www.aoa.org/healthy-eyes/eye-and-vision-conditions/computer-vision-syndrome', guide.read_text())
            privacy = SITE / prefix / 'privacy/index.html'
            self.assertTrue(privacy.is_file())
            self.assertIn('GitHub', privacy.read_text())
        english = (SITE / 'en/faq/index.html').read_text()
        for fact in ['gaze', 'iPhone', 'iCloud Drive', 'medical']:
            self.assertIn(fact, english)

    def test_opt_in_mac_backup_and_os_cloud_sync_are_disclosed(self):
        paths = [p + r + 'index.html' for p in ['', 'en/'] for r in ['', 'download/', 'faq/', 'privacy/']]
        paths += ['facts.md', 'llms.txt']
        for path in paths:
            text = (SITE / path).read_text()
            with self.subTest(path=path):
                for fact in ['iCloud Drive', '30', 'CloudKit']:
                    self.assertIn(fact, text)
                for inaccurate in ['没有云端自动同步', '无云端自动同步', 'No automatic cloud sync', 'no cloud autosync', 'no app account system or automatic cloud sync', 'exports/backups are user-initiated']:
                    self.assertNotIn(inaccurate, text)
        self.assertIn('class="nowrap">歇会儿', (SITE / 'index.html').read_text())

    def test_home_screenshots_identify_demonstration_data(self):
        for route, marker in [('', '演示'), ('en/', 'Demo')]:
            text = (SITE / route / 'index.html').read_text()
            self.assertGreaterEqual(text.count(marker), 3)
            self.assertNotIn('轻量', text)

    def test_image_dimensions_match_supplied_pngs(self):
        for route, page in self.pages.items():
            for tag, attrs in page.tags:
                if tag != 'img': continue
                path = SITE / attrs['src'].removeprefix(urlsplit(self.base).path)
                data = path.read_bytes()
                self.assertTrue(data.startswith(b'\x89PNG'))
                actual_width, actual_height = struct.unpack('>II', data[16:24])
                width, height = int(attrs['width']), int(attrs['height'])
                with self.subTest(route=route, image=path.name):
                    self.assertAlmostEqual(width / height, actual_width / actual_height, places=4)

    def test_generator_supports_other_project_base_and_is_deterministic(self):
        path = ROOT / 'tools/build_site.py'
        self.assertTrue(path.is_file())
        spec = importlib.util.spec_from_file_location('breather_build_site', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        config = dict(self.config, siteUrl='https://example.test/projects/breather/', repositoryUrl='https://github.com/example/Breather')
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            module.build(config, output)
            first = {str(p.relative_to(output)): p.read_bytes() for p in output.rglob('*') if p.is_file()}
            module.build(config, output)
            self.assertEqual(first, {str(p.relative_to(output)): p.read_bytes() for p in output.rglob('*') if p.is_file()})
            html = (output / 'en/download/index.html').read_text()
            self.assertIn('https://example.test/projects/breather/en/download/', html)
            self.assertIn('/projects/breather/assets/style.css', html)
            self.assertNotIn(self.base, html)


if __name__ == '__main__':
    unittest.main()
