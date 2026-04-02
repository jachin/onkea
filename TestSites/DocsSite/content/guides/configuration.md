---
title: "Configuration"
date: 2026-01-01T09:00:00Z
draft: false
weight: 20
tags:
  - setup
  - config
---

## Config file

Oneka reads `oneka.toml` from the project root.

```toml
[site]
path = "./MySite"

[editor]
wrap = 80
```

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `ONEKA_SITE` | `""` | Path to the Hugo site root |
| `ONEKA_WRAP` | `80` | Line wrap width for the editor |
