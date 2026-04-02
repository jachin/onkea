---
title: "Installation"
date: 2026-01-01T09:00:00Z
draft: false
weight: 10
tags:
  - setup
  - install
---

## Requirements

- macOS 13+ or Linux
- Go 1.21+

## Steps

1. Download the latest release.
2. Move the binary to `/usr/local/bin`.
3. Verify with `oneka --version`.

```bash
curl -Lo oneka https://example.local/releases/latest/oneka-darwin-arm64
chmod +x oneka
mv oneka /usr/local/bin/
oneka --version
```
