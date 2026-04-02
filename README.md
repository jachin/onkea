# Oneka

Oneka is a native macOS editor for Hugo sites built with SwiftUI. It is aimed at writing and managing Hugo content without leaving a desktop editing workflow.

## What It Does

- Opens an existing Hugo site and loads its content directly from disk
- Lists posts and pages, with post browsing by date, tags, or categories
- Edits Markdown content with syntax highlighting and configurable editor color schemes
- Shows a live preview by running a local `hugo server`
- Saves individual files or all pending edits
- Updates post metadata such as `lastmod` using configurable Hugo date formats
- Exposes site settings and editor preferences inside the app

## Requirements

- macOS with Xcode to build the app
- Hugo installed locally
- Hugo `v0.158.0` or newer

If Hugo is missing or the installed version is older than the required minimum, Oneka blocks editing until a compatible version is available.

## Project Layout

- `Oneka/Oneka/`: SwiftUI app source
- `Oneka/OnekaTests/`: unit tests
- `Oneka/OnekaUITests/`: UI tests
- `Oneka/hugo/`: bundled Hugo source tree used by this project

## Development

Open the project in Xcode and build the `Oneka` scheme. The app uses SwiftUI, SwiftData, and the modern Apple testing stack already present in the repository.

## License

This repository is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
