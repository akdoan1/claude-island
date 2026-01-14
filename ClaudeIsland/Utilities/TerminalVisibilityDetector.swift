//
//  TerminalVisibilityDetector.swift
//  ClaudeIsland
//
//  Detects if terminal windows are visible on current space
//

import AppKit
import CoreGraphics

struct TerminalVisibilityDetector {
    /// Check if the frontmost (active) application is a terminal
    static func isTerminalFrontmost() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }

        return TerminalAppRegistry.isTerminalBundle(bundleId)
    }

    /// Check if a Claude session's terminal window is visible on the current space
    /// - Parameter sessionPid: The PID of the Claude process
    /// - Returns: true if the session's terminal has a visible, unobscured window on the current space
    static func isSessionTerminalVisible(sessionPid: Int) -> Bool {
        let tree = ProcessTreeBuilder.shared.buildTree()

        // Get all on-screen windows (returned in front-to-back z-order)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        // Find the terminal window for this session and check if it's visible
        var windowsAbove: [CGRect] = []

        for window in windowList {
            guard let ownerPid = window[kCGWindowOwnerPID as String] as? Int,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  layer == 0 else { continue }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            // Check if this window belongs to the session's terminal
            if ProcessTreeBuilder.shared.isDescendant(targetPid: sessionPid, ofAncestor: ownerPid, tree: tree) {
                // Found the terminal window - check if it's mostly visible
                return !isWindowMostlyObscured(windowBounds: bounds, windowsAbove: windowsAbove)
            }

            // Track windows we've seen (they're in front of windows we haven't seen yet)
            windowsAbove.append(bounds)
        }

        return false
    }

    /// Check if a window is mostly obscured by windows above it
    /// - Parameters:
    ///   - windowBounds: The bounds of the window to check
    ///   - windowsAbove: Array of bounds for windows in front of this one
    /// - Returns: true if more than 50% of the window is covered
    private static func isWindowMostlyObscured(windowBounds: CGRect, windowsAbove: [CGRect]) -> Bool {
        let windowArea = windowBounds.width * windowBounds.height
        guard windowArea > 0 else { return true }

        // Calculate total overlap from windows above
        // Note: This is a simplified calculation that may overcount if covering windows overlap each other
        var coveredArea: CGFloat = 0
        for aboveBounds in windowsAbove {
            let intersection = windowBounds.intersection(aboveBounds)
            if !intersection.isNull {
                coveredArea += intersection.width * intersection.height
            }
        }

        // Consider obscured if >50% covered
        return coveredArea / windowArea > 0.5
    }

    /// Check if a Claude session is currently focused (user is looking at it)
    /// - Parameter sessionPid: The PID of the Claude process
    /// - Returns: true if the session's terminal is frontmost and (for tmux) the pane is active
    static func isSessionFocused(sessionPid: Int) async -> Bool {
        // If no terminal is frontmost, session is definitely not focused
        guard isTerminalFrontmost() else {
            return false
        }

        let tree = ProcessTreeBuilder.shared.buildTree()
        let isInTmux = ProcessTreeBuilder.shared.isInTmux(pid: sessionPid, tree: tree)

        if isInTmux {
            // For tmux sessions, check if the session's pane is active
            return await TmuxTargetFinder.shared.isSessionPaneActive(claudePid: sessionPid)
        } else {
            // For non-tmux sessions, check if the session is a descendant of the frontmost app
            // This handles terminal architectures where child processes (like iTermServer or Warp's
            // terminal-server) run the shell, but the main app process is what's reported as frontmost
            guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
                return false
            }

            let frontmostPid = Int(frontmostApp.processIdentifier)
            return ProcessTreeBuilder.shared.isDescendant(targetPid: sessionPid, ofAncestor: frontmostPid, tree: tree)
        }
    }
}
