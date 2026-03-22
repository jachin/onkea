//
//  YouGoHugoTests.swift
//  YouGoHugoTests
//
//  Created by Jachin Rupe on 3/20/26.
//

import Testing
@testable import YouGoHugo

struct YouGoHugoTests {
    @Test
    func resolvesHugoFromConfiguredExecutable() async throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let executableURL = temporaryDirectory.appendingPathComponent("hugo")
        try Data().write(to: executableURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let resolvedURL = hugoExecutableURL(environment: ["HUGO_EXECUTABLE": executableURL.path])

        #expect(resolvedURL == executableURL)
    }

    @Test
    func resolvesHugoFromFallbackPathWhenPathIsMissing() async throws {
        let executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/hugo")

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return
        }

        let resolvedURL = hugoExecutableURL(environment: [:])

        #expect(resolvedURL == executableURL)
    }
}
