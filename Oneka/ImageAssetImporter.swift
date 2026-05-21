import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageImportOptions: Equatable {
    var maxPixelSize = 2400
    var jpegQuality = 0.82
}

struct ImageImportStatus: Equatable {
    var message: String
    var fractionCompleted: Double
}

struct ImportedImageAsset: Equatable {
    let fileURL: URL
    let markdownPath: String
    let altText: String
}

enum ImageImportSource: Sendable {
    case file(URL)
    case data(Data, suggestedFilename: String?)
}

enum ImageAssetImportError: LocalizedError {
    case unsupportedImage
    case destinationUnavailable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            "The selected file could not be read as an image."
        case .destinationUnavailable:
            "Oneka could not create a destination for the imported image."
        case .encodingFailed:
            "Oneka could not write the imported image as a JPEG."
        }
    }
}

struct ImageAssetImporter {
    var options = ImageImportOptions()

    nonisolated func importImage(
        from source: ImageImportSource,
        into siteURL: URL,
        for item: HugoContentItem,
        siteBasePath: String? = nil,
        preferredFilenameBase: String? = nil,
        progress: @escaping @Sendable (ImageImportStatus) -> Void
    ) async throws -> ImportedImageAsset {
        try await Task.detached(priority: .userInitiated) {
            progress(ImageImportStatus(message: "Preparing import...", fractionCompleted: 0.1))

            let destination = try Self.destination(
                in: siteURL,
                for: item,
                sourceFilename: source.suggestedFilename,
                preferredFilenameBase: preferredFilenameBase,
                siteBasePath: siteBasePath
            )

            progress(ImageImportStatus(message: "Reading image...", fractionCompleted: 0.25))
            let imageSource = try Self.createImageSource(from: source)

            progress(ImageImportStatus(message: "Resizing image...", fractionCompleted: 0.55))
            let image = try Self.createDisplayImage(from: imageSource, maxPixelSize: options.maxPixelSize)

            try FileManager.default.createDirectory(
                at: destination.directoryURL,
                withIntermediateDirectories: true
            )

            progress(ImageImportStatus(message: "Writing JPEG...", fractionCompleted: 0.8))
            try Self.writeJPEG(
                image,
                to: destination.fileURL,
                quality: options.jpegQuality
            )

            progress(ImageImportStatus(message: "Imported image", fractionCompleted: 1.0))
            return ImportedImageAsset(
                fileURL: destination.fileURL,
                markdownPath: destination.markdownPath,
                altText: destination.altText
            )
        }.value
    }

    nonisolated private static func createImageSource(from source: ImageImportSource) throws -> CGImageSource {
        switch source {
        case .file(let url):
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                throw ImageAssetImportError.unsupportedImage
            }
            return imageSource
        case .data(let data, _):
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw ImageAssetImportError.unsupportedImage
            }
            return imageSource
        }
    }

    nonisolated private static func createDisplayImage(from source: CGImageSource, maxPixelSize: Int) throws -> CGImage {
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
            return thumbnail
        }

        let imageOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, imageOptions as CFDictionary) else {
            throw ImageAssetImportError.unsupportedImage
        }
        return image
    }

    nonisolated private static func writeJPEG(_ image: CGImage, to outputURL: URL, quality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageAssetImportError.destinationUnavailable
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageAssetImportError.encodingFailed
        }
    }

    nonisolated private static func destination(
        in siteURL: URL,
        for item: HugoContentItem,
        sourceFilename: String?,
        preferredFilenameBase: String?,
        siteBasePath: String?
    ) throws -> ImageImportDestination {
        let contentURL = siteURL.appendingPathComponent(item.path)
        let contentFilename = contentURL.lastPathComponent.lowercased()
        let baseName = sanitizedFilenameBase(
            from: preferredFilenameBase ?? sourceFilename ?? contentURL.deletingPathExtension().lastPathComponent
        )
        let altText = altTextFromFilenameBase(baseName)

        if contentFilename == "index.md" || contentFilename == "_index.md" {
            let directoryURL = contentURL.deletingLastPathComponent().appendingPathComponent("images")
            let fileURL = uniqueFileURL(in: directoryURL, baseName: baseName, extension: "jpg")
            return ImageImportDestination(
                directoryURL: directoryURL,
                fileURL: fileURL,
                markdownPath: absoluteMarkdownPath(
                    under: pagePublicPath(for: item, siteBasePath: siteBasePath),
                    components: ["images", fileURL.lastPathComponent]
                ),
                altText: altText
            )
        }

        let contentSlug = sanitizedFilenameBase(
            from: item.slug.isEmpty ? contentURL.deletingPathExtension().lastPathComponent : item.slug
        )
        let directoryURL = siteURL
            .appendingPathComponent("static")
            .appendingPathComponent("images")
            .appendingPathComponent(contentSlug)
        let fileURL = uniqueFileURL(in: directoryURL, baseName: baseName, extension: "jpg")

        return ImageImportDestination(
            directoryURL: directoryURL,
            fileURL: fileURL,
            markdownPath: absoluteMarkdownPath(components: ["images", contentSlug, fileURL.lastPathComponent]),
            altText: altText
        )
    }

    nonisolated private static func absoluteMarkdownPath(
        under basePath: String = "",
        components: [String]
    ) -> String {
        let baseComponents = basePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        return "/" + (baseComponents + components).joined(separator: "/")
    }

    nonisolated private static func pagePublicPath(for item: HugoContentItem, siteBasePath: String?) -> String {
        let permalinkPath: String
        if let permalinkURL = URL(string: item.permalink), permalinkURL.scheme != nil {
            permalinkPath = permalinkURL.path
        } else {
            permalinkPath = item.permalink
        }

        let trimmedPath = permalinkPath
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? permalinkPath
        var components = trimmedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let baseComponents = siteBasePathComponents(from: siteBasePath)

        if components.starts(with: baseComponents) {
            components.removeFirst(baseComponents.count)
        }

        return components.joined(separator: "/")
    }

    nonisolated private static func siteBasePathComponents(from siteBasePath: String?) -> [String] {
        guard let siteBasePath, !siteBasePath.isEmpty else {
            return []
        }

        let path: String
        if let url = URL(string: siteBasePath), url.scheme != nil {
            path = url.path
        } else {
            path = siteBasePath
        }

        return path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    nonisolated private static func uniqueFileURL(in directoryURL: URL, baseName: String, extension pathExtension: String) -> URL {
        let fileManager = FileManager.default
        var candidate = directoryURL.appendingPathComponent(baseName).appendingPathExtension(pathExtension)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directoryURL
                .appendingPathComponent("\(baseName)-\(suffix)")
                .appendingPathExtension(pathExtension)
            suffix += 1
        }

        return candidate
    }

    nonisolated private static func sanitizedFilenameBase(from value: String) -> String {
        let name = URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = name.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .lowercased()

        return collapsed.isEmpty ? "image" : collapsed
    }

    nonisolated private static func altTextFromFilenameBase(_ baseName: String) -> String {
        baseName
            .split(separator: "-", omittingEmptySubsequences: true)
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}

private struct ImageImportDestination {
    let directoryURL: URL
    let fileURL: URL
    let markdownPath: String
    let altText: String
}

private extension ImageImportSource {
    nonisolated var suggestedFilename: String? {
        switch self {
        case .file(let url):
            url.lastPathComponent
        case .data(_, let suggestedFilename):
            suggestedFilename
        }
    }
}
