// Copyright © 2026 Gafie Garcia.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Captures one on-screen window of a running app, by name, and nothing else.
//
//   swift apps/macos/Tools/window-shot.swift Scriber /tmp/scriber.png
//
// Written because the obvious alternative is not acceptable: a plain
// `screencapture` takes the whole display, which means Gaf's open windows, his
// files, and whatever he happens to be reading all land in a transcript. This
// asks the window server for the target app's windows and captures only the
// frontmost one, so a visual check costs him no privacy.
//
// Needs Screen Recording permission for whatever runs it, the same as
// `screencapture` itself. It does not move the pointer, take focus, or touch the
// keyboard, so unlike the XCUITest suite it is safe to run while the Mac is in
// use — the app under test does not even have to be frontmost.

import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: window-shot.swift <app name> <output.png>\n".utf8))
    exit(2)
}
let appName = arguments[1]
let outputPath = arguments[2]

guard let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] else {
    FileHandle.standardError.write(Data("could not read the window list\n".utf8))
    exit(1)
}

// On-screen order is front to back, so the first match is the one the user would
// call "the window". Zero-height entries are shadows and title bar helpers.
let match = windows.first { window in
    guard window[kCGWindowOwnerName as String] as? String == appName else { return false }
    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let height = bounds["Height"] as? Double else { return false }
    return height > 100
}

guard let match, let windowID = match[kCGWindowNumber as String] as? Int else {
    FileHandle.standardError.write(Data("no on-screen window found for \(appName)\n".utf8))
    exit(1)
}

let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
// -x silences the shutter, -o drops the drop shadow, -l names the window.
capture.arguments = ["-x", "-o", "-l\(windowID)", outputPath]
try capture.run()
capture.waitUntilExit()
exit(capture.terminationStatus)
