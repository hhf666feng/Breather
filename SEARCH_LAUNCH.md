# SEO / GEO launch and ownership checklist

## Implemented foundation

- Public, audited repository with a clean initial history; private research and original history remain outside this repository.
- Static Chinese and English product pages rendered as HTML (not an empty JS shell), with real internal links, download/version/system requirements, FAQ, privacy and an educational 20-20-20 guide.
- Unique titles/descriptions, self-canonicals, reciprocal hreflang, social previews, actual SoftwareApplication/WebSite/Breadcrumb data without invented ratings or medical guarantees.
- Sitemap and machine-readable product facts plus llms.txt. These aid discovery; llms.txt is not a universal search-engine requirement or an indexing guarantee.
- No third-party analytics, remote fonts or scripts. GitHub hosting/download services may maintain access logs under their own policies.

## Stable public entry points

- Website: https://hhf666feng.github.io/Breather/
- English: https://hhf666feng.github.io/Breather/en/
- Sitemap: https://hhf666feng.github.io/Breather/sitemap.xml
- AI reading guide: https://hhf666feng.github.io/Breather/llms.txt
- Repository: https://github.com/hhf666feng/Breather

The site's base URL is stored in public-config.json. Update that first if adding a custom domain, regenerate pages, and configure both DNS/Pages before changing canonicals. Do not use an unverified domain.

## Owner actions still required (not performed automatically)

1. Sign in to [Google Search Console](https://search.google.com/search-console/) with the intended owner account. Add a URL-prefix property for the exact project URL above. Choose HTML-file or meta-tag verification, supply that public token/file, then verify. Do not send login secrets in chat.
2. Submit sitemap.xml in that verified property. Inspect the Chinese homepage, English homepage and download pages, then request indexing where offered. Submission is not successful indexing.
3. In [Bing Webmaster Tools](https://www.bing.com/webmasters/), import the verified Search Console property or use its official verification flow, then submit the sitemap.
4. If using IndexNow, obtain and host an authentic key file before submission; no fabricated key or fake ownership token is included.
5. For Google/Bing/AI search availability, periodically inspect actual indexed URLs and search-performance reports. Do not infer inclusion from an HTTP 200 or a successful deployment.
6. For Baidu or other services, follow their authenticated site-verification flow where the host/project URL is supported; a verified custom domain may be more practical. No promise of access or inclusion in China.

## Project-path crawler limitation

This is GitHub Pages at a project path, not the origin owner. The authoritative robots.txt location is the origin root `https://hhf666feng.github.io/robots.txt`, not `/Breather/robots.txt`. No other repository or user-level Pages site has been changed. Sitemap can be submitted directly; per-page robots metadata can be verified in the HTML. A llms.txt inside this project is advisory and linked from pages, not proof of automatic AI ingestion.

## Content priorities and measurement

Primary Chinese intents: 歇会儿, Mac休息提醒, Windows休息提醒, 用眼时长记录, 20-20-20提醒。English: Breather eye break reminder, Mac eye break reminder, Windows screen break timer. Use them naturally in useful product documentation, not keyword stuffing or repetitive doorway pages.

Publish future changes with a visible version, accurate platform differences, screenshots using demo data, and sources for health-related education. Never claim the timer measures clinical fatigue, cures eye disease, or proves a person is looking at the display.

Metrics after verification: valid indexed pages, impressions/clicks by non-brand queries, download link clicks if privacy-respecting measurement is later explicitly enabled, and citations that actually name/link the product. No analytics collection is currently enabled.

## References

- [Google AI features and your website](https://developers.google.com/search/docs/appearance/ai-features)
- [Google sitemap guidance](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap)
- [Google robots.txt location and scope](https://developers.google.com/search/docs/crawling-indexing/robots/intro)
- [Bing Webmaster Tools](https://www.bing.com/webmasters/)
