// Silicon Info
// Copyright (C) 2026 Ray Munro
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import Foundation

/// Hands "free memory" requests to the privileged loop. The loop (started with the administrator prompt) watches for a
/// trigger file whose name contains a per-install secret, so only this app can ask it to run `purge`.
enum MemoryPurger {
    /// Stable across launches so a still-running privileged loop from a previous launch keeps working.
    static let token: String = {
        let key = "purgeToken"
        if let t = UserDefaults.standard.string(forKey: key) { return t }
        let t = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
        UserDefaults.standard.set(String(t), forKey: key)
        return String(t)
    }()

    static var triggerPath: String { "/private/tmp/siliconinfo-purge-\(token)" }

    static func trigger() { FileManager.default.createFile(atPath: triggerPath, contents: nil) }
    static var triggerPending: Bool { FileManager.default.fileExists(atPath: triggerPath) }
    static func cancelTrigger() { try? FileManager.default.removeItem(atPath: triggerPath) }
}

extension Sampler {
    /// Asks for cached memory to be freed. Goes through the same path as a tap on the widget.
    func requestPurge() { SharedStore.requestPurge() }

    /// Runs once per tick: starts a purge when one was requested and reports the result when it finishes.
    func handlePurge() {
        if SharedStore.consumePurgeRequest(), purgeStarted == nil {
            guard feedLive else { setPurgeNote("Needs admin access"); return }
            purgeBeforeCached = mem.cached
            purgeStarted = Date()
            MemoryPurger.trigger()
        }
        guard let started = purgeStarted else { return }
        let elapsed = Date().timeIntervalSince(started)
        if !MemoryPurger.triggerPending, elapsed >= 4 {          // the loop removes the file after purge finishes
            let freed = max(purgeBeforeCached - mem.cached, 0)
            setPurgeNote(freed > 50_000_000 ? "Freed \(gb(freed))" : "Nothing to free")
            purgeStarted = nil
        } else if elapsed > 20 {
            MemoryPurger.cancelTrigger()
            setPurgeNote("Could not free memory")
            purgeStarted = nil
        }
    }

    private func setPurgeNote(_ text: String) {
        purgeNote = text
        purgeNoteDate = Date()
        publishToWidget(tick: 10)       // writes the snapshot and reloads the widget right away
    }
}
