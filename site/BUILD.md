# Breather Public Site Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Publish ten crawlable Chinese/English product, download, FAQ, privacy, and educational pages with accurate machine-readable facts.

**Architecture:** A dependency-free Python generator reads the repository's public-config.json and renders deterministic static HTML and discovery documents into site/. Shared content and navigation ensure reciprocal language alternatives. Brand assets are supplied separately and never rewritten.

**Tech Stack:** Python stdlib, HTML5, CSS, unittest, HTMLParser, ElementTree.

---

## Task 1 — Specify the public contract (test first)

- Create Tests/test_site.py with real generated-file assertions: exactly ten page routes, unique titles/descriptions, canonical and reciprocal zh-CN/en/x-default links, all local links and images, valid JSON-LD without ratings/reviews, exact per-platform versions/downloads, and consistent sitemap/facts/llms.
- Run `python3 -m unittest discover -s Tests -p test_site.py -v`; confirm failure because tools/build_site.py is absent.

## Task 2 — Generate the product site

- Create tools/build_site.py. Read siteUrl/repositoryUrl/macVersion/windowsVersion from public-config.json, not hardcoded deployment URLs.
- Emit Chinese root and English en/ home, download/, faq/, privacy/, guidance/20-20-20/ pages. Include indexable visible copy, explicit platform limits and unsigned-install notices.
- Emit site/assets/style.css, sitemap.xml, llms.txt, facts.md and informational robots.txt. Keep supplied logo.png, mac-dashboard.png and windows-dashboard.png unchanged.
- Add SoftwareApplication entities for separate native macOS and Electron Windows products with separate versions and download links; declare free offers with explicit USD currency. Never add ratings, review, medical efficacy, or license claims.
- Keep all font/script/image loads local; no external analytics.

## Task 3 — Verify and freeze

- Run `python3 tools/build_site.py` and `python3 -m unittest discover -s Tests -p test_site.py -v` until green.
- Review generator and generated home/download/privacy/guide markup; verify the provided PNGs are included.
- Report exact commands/results and freeze delegated files for Lead review. No git operations or application/config changes.

## Deployment notes

Run the generator from any directory with `python3 tools/build_site.py` (script resolves the repository root). Publish the **site/** directory as the GitHub Pages artifact. The configured URL includes the **/Breather/** project prefix; canonical URLs, assets and navigation retain it. No JavaScript is required.

A robots.txt served at /Breather/robots.txt is informational only: robots rules are authoritative only at the origin's /robots.txt. This project does not control the owner.github.io origin-root file and does not claim project-level crawl directives are honored. The sitemap and visible links provide discovery without relying on robots authority. llms.txt and facts.md are convenience documents, not a promise of crawler adoption or ranking.

External educational source: American Optometric Association, https://www.aoa.org/healthy-eyes/eye-and-vision-conditions/computer-vision-syndrome (verified content describes a 20-second break looking 20 feet away every 20 minutes). The site distinguishes this general habit from product efficacy and directs persistent symptoms to an eye-care professional.
