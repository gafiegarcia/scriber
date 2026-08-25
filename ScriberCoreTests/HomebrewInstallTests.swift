import Foundation
import Testing
@testable import ScriberCore

/// Builds the layout a cask actually leaves behind: the app in one place, and a
/// Caskroom holding a symlink that points at it.
@Suite("Homebrew install detection")
struct HomebrewInstallTests {
    private struct Layout {
        let root: URL
        let caskroom: String
        let appPath: String
    }

    private func makeLayout(
        caskName: String = "scriber",
        version: String = "0.9.0",
        linkingToApp: Bool = true
    ) throws -> Layout {
        let manager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scriber-brew-\(UUID().uuidString)")
        let applications = root.appendingPathComponent("Applications")
        let app = applications.appendingPathComponent("Scriber.app")
        try manager.createDirectory(at: app, withIntermediateDirectories: true)

        let staged = root
            .appendingPathComponent("Caskroom")
            .appendingPathComponent(caskName)
            .appendingPathComponent(version)
        try manager.createDirectory(at: staged, withIntermediateDirectories: true)
        if linkingToApp {
            try manager.createSymbolicLink(
                at: staged.appendingPathComponent("Scriber.app"),
                withDestinationURL: app
            )
        }
        return Layout(
            root: root,
            caskroom: root.appendingPathComponent("Caskroom").path,
            appPath: app.path
        )
    }

    @Test("A Caskroom link pointing at this bundle is a Homebrew install")
    func recognisesManagedInstall() throws {
        let layout = try makeLayout()
        #expect(HomebrewInstall.manages(
            bundlePath: layout.appPath,
            caskroomRoots: [layout.caskroom]
        ))
    }

    /// The case a folder check gets wrong: Homebrew's record is still there, but
    /// the app it points at is not the one running.
    @Test("A Caskroom recording a different app is not this install")
    func rejectsUnrelatedApp() throws {
        let layout = try makeLayout()
        let elsewhere = layout.root.appendingPathComponent("Builds/Scriber.app")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        #expect(!HomebrewInstall.manages(
            bundlePath: elsewhere.path,
            caskroomRoots: [layout.caskroom]
        ))
    }

    @Test("A Caskroom holding no link is not a Homebrew install")
    func rejectsCaskroomWithoutLink() throws {
        let layout = try makeLayout(linkingToApp: false)
        #expect(!HomebrewInstall.manages(
            bundlePath: layout.appPath,
            caskroomRoots: [layout.caskroom]
        ))
    }

    @Test("Another cask's Caskroom is not this install")
    func rejectsDifferentCask() throws {
        let layout = try makeLayout(caskName: "ghostty")
        #expect(!HomebrewInstall.manages(
            bundlePath: layout.appPath,
            caskroomRoots: [layout.caskroom]
        ))
    }

    @Test("A missing Caskroom is not a Homebrew install")
    func rejectsMissingCaskroom() {
        #expect(!HomebrewInstall.manages(
            bundlePath: "/Applications/Scriber.app",
            caskroomRoots: ["/nowhere/Caskroom"]
        ))
    }

    /// Homebrew keeps every installed version in its own folder, and an upgrade
    /// can leave an older one behind.
    @Test("The link is found whichever version folder holds it")
    func searchesEveryVersion() throws {
        let layout = try makeLayout(version: "0.9.1")
        let stale = URL(fileURLWithPath: layout.caskroom)
            .appendingPathComponent("scriber/0.8.0")
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        #expect(HomebrewInstall.manages(
            bundlePath: layout.appPath,
            caskroomRoots: [layout.caskroom]
        ))
    }
}
