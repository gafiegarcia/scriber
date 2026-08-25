import Foundation

/// Whether Homebrew is managing the running app.
///
/// A cask moves the app to `/Applications` and leaves a symlink in its Caskroom
/// pointing back at it, so the question is whether any of those links resolves
/// to this bundle. That a Caskroom folder exists is not enough on its own: it
/// outlives the app it recorded being replaced by hand, and would go on
/// claiming an install Homebrew no longer put there.
public enum HomebrewInstall {
    /// Apple silicon only ever uses the first, and Scriber runs nowhere else.
    /// The second costs one entry and covers a Mac that carried its Homebrew
    /// across. A prefix set anywhere else reads as unmanaged, which costs the
    /// user the ordinary download route rather than anything worse.
    public static let defaultCaskroomRoots = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]

    /// What a Homebrew install runs instead of downloading a release. The tap is
    /// not named: an installed cask resolves by its short name.
    public static let upgradeCommand = "brew upgrade --cask scriber"

    /// Matches on the resolved path rather than the app's name, so a cask that
    /// renames its artifact is still recognised.
    public static func manages(
        bundlePath: String,
        caskName: String = "scriber",
        caskroomRoots: [String] = defaultCaskroomRoots,
        fileManager: FileManager = .default
    ) -> Bool {
        let bundle = URL(fileURLWithPath: bundlePath).resolvingSymlinksInPath().path
        return caskroomRoots.contains { root in
            let cask = URL(fileURLWithPath: root).appendingPathComponent(caskName)
            let versions = (try? fileManager.contentsOfDirectory(
                at: cask,
                includingPropertiesForKeys: nil
            )) ?? []
            return versions.contains { version in
                let staged = (try? fileManager.contentsOfDirectory(
                    at: version,
                    includingPropertiesForKeys: nil
                )) ?? []
                return staged.contains { entry in
                    entry.pathExtension == "app"
                        && entry.resolvingSymlinksInPath().path == bundle
                }
            }
        }
    }
}
