# Security Policy

## Supported Versions

Only the latest published LexiRay release receives security fixes.

## Reporting a Vulnerability

Please report security issues privately by emailing the maintainer listed on the
GitHub profile for `tensornull`.

Do not open a public issue for vulnerabilities involving credentials, local
permissions, clipboard contents, translation provider requests, or release
artifacts.

Include:

- Affected version or commit.
- macOS and Xcode versions if relevant.
- Reproduction steps.
- Expected and actual impact.
- Whether credentials, clipboard data, selected text, or screenshots are exposed.

## Local Data

LexiRay handles selected text, clipboard contents, OCR regions, provider API
keys, and translation history. Changes touching those areas require focused
tests and a short privacy/security note in the PR.
