import AppKit
import XCTest

@testable import TairiApp

final class TerminalHeaderIconResolverTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directoryURL in temporaryDirectories {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        temporaryDirectories.removeAll()
    }

    func testResolvedProjectIconURLFindsWellKnownCandidate() throws {
        let projectURL = try makeTemporaryDirectory(prefix: "tairi-icon-candidate-")
        try "{}".write(
            to: projectURL.appendingPathComponent("package.json", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let faviconURL = projectURL.appendingPathComponent("public/favicon.png", isDirectory: false)
        try writeTestPNG(to: faviconURL)

        XCTAssertEqual(
            TerminalHeaderIconResolver.resolvedProjectIconURL(
                forWorkingDirectory: projectURL.path(percentEncoded: false)
            )?.standardizedFileURL,
            faviconURL.standardizedFileURL
        )
    }

    func testResolvedProjectIconURLFindsSwiftAppIconFromNestedSourceDirectory() throws {
        let projectURL = try makeTemporaryDirectory(prefix: "tairi-icon-swift-")
        try "// swift-tools-version: 6.0".write(
            to: projectURL.appendingPathComponent("Package.swift", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let sourceDirectoryURL = projectURL.appendingPathComponent("Sources/MyApp", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)

        let iconURL = projectURL.appendingPathComponent("Assets/AppIcon.png", isDirectory: false)
        try writeTestPNG(to: iconURL)

        XCTAssertEqual(
            TerminalHeaderIconResolver.resolvedProjectIconURL(
                forWorkingDirectory: sourceDirectoryURL.path(percentEncoded: false)
            )?.standardizedFileURL,
            iconURL.standardizedFileURL
        )
    }

    func testResolvedProjectIconURLResolvesHTMLIconMetadata() throws {
        let projectURL = try makeTemporaryDirectory(prefix: "tairi-icon-html-")
        let iconURL = projectURL.appendingPathComponent("public/brand/logo.png", isDirectory: false)
        try writeTestPNG(to: iconURL)
        try """
        <!doctype html>
        <html>
        <head>
          <link rel="icon" href="/brand/logo.png">
        </head>
        </html>
        """.write(
            to: projectURL.appendingPathComponent("index.html", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(
            TerminalHeaderIconResolver.resolvedProjectIconURL(
                forWorkingDirectory: projectURL.path(percentEncoded: false)
            )?.standardizedFileURL,
            iconURL.standardizedFileURL
        )
    }

    func testResolvedProjectIconURLFindsPythonStaticIcon() throws {
        let projectURL = try makeTemporaryDirectory(prefix: "tairi-icon-python-")
        try """
        [project]
        name = "example"
        version = "0.1.0"
        """.write(
            to: projectURL.appendingPathComponent("pyproject.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let iconURL = projectURL.appendingPathComponent("static/icon.png", isDirectory: false)
        try writeTestPNG(to: iconURL)

        XCTAssertEqual(
            TerminalHeaderIconResolver.resolvedProjectIconURL(
                forWorkingDirectory: projectURL.path(percentEncoded: false)
            )?.standardizedFileURL,
            iconURL.standardizedFileURL
        )
    }

    func testResolvedProjectIconURLResolvesObjectMetadataWhenHrefPrecedesRel() throws {
        let projectURL = try makeTemporaryDirectory(prefix: "tairi-icon-object-")
        let iconURL = projectURL.appendingPathComponent("public/brand/object.png", isDirectory: false)
        try writeTestPNG(to: iconURL)

        let sourceDirectoryURL = projectURL.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)
        try """
        const links = [{ href: "/brand/object.png", rel: "icon" }];
        """.write(
            to: sourceDirectoryURL.appendingPathComponent("root.tsx", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(
            TerminalHeaderIconResolver.resolvedProjectIconURL(
                forWorkingDirectory: projectURL.path(percentEncoded: false)
            )?.standardizedFileURL,
            iconURL.standardizedFileURL
        )
    }

    func testResolvedProjectIconURLFindsRustTauriIcon() throws {
        let projectURL = try makeTemporaryDirectory(prefix: "tairi-icon-rust-")
        try """
        [package]
        name = "example"
        version = "0.1.0"
        edition = "2021"
        """.write(
            to: projectURL.appendingPathComponent("Cargo.toml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let iconURL = projectURL.appendingPathComponent("src-tauri/icons/icon.png", isDirectory: false)
        try writeTestPNG(to: iconURL)

        XCTAssertEqual(
            TerminalHeaderIconResolver.resolvedProjectIconURL(
                forWorkingDirectory: projectURL.path(percentEncoded: false)
            )?.standardizedFileURL,
            iconURL.standardizedFileURL
        )
    }

    func testResolvedProjectIconURLRejectsPathsOutsideProject() throws {
        let projectURL = try makeTemporaryDirectory(prefix: "tairi-icon-outside-project-")
        let outsideIconURL = projectURL.deletingLastPathComponent().appendingPathComponent("outside.png", isDirectory: false)
        try writeTestPNG(to: outsideIconURL)
        try """
        <link rel="icon" href="../outside.png">
        """.write(
            to: projectURL.appendingPathComponent("index.html", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertNil(
            TerminalHeaderIconResolver.resolvedProjectIconURL(
                forWorkingDirectory: projectURL.path(percentEncoded: false)
            )
        )
    }

    private func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        temporaryDirectories.append(directoryURL)
        return directoryURL
    }

    private func writeTestPNG(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemTeal.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Failed to create test PNG data")
            return
        }

        try pngData.write(to: url)
    }
}
