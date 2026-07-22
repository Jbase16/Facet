import Foundation
import FacetData
import Intents

/// Focus (Do Not Disturb) state via `INFocusStatusCenter`.
///
/// The public API is deliberately narrow, and this source does not pretend
/// otherwise: `INFocusStatus` exposes exactly one thing — `isFocused`,
/// whether *some* Focus is active. Which Focus ("Deep Work", "Sleep",
/// "Personal") is not readable by third-party apps at all, so nothing here
/// invents a mode name. `focus.status` is display-ready On/Off copy, not a
/// label for a mode we don't have.
///
/// Two gates sit between the prompt and a real value: this app's
/// authorization, and the user's per-Focus "Share Focus Status" switch in
/// Settings. With sharing off, `isFocused` comes back nil even when
/// authorized — read as off, because "the user didn't tell us" and "not
/// focused" are indistinguishable from out here.
struct FocusSource: DataSourceProvider {
    let descriptor = DataSourceDescriptor(
        id: "focus",
        displayName: "Focus",
        cadence: .frequent,
        providedPaths: ["focus.isOn", "focus.status"]
    )

    func fetch() async throws -> DataSnapshot {
        guard Self.authorizationGranted else {
            // Throwing keeps the pipeline on its last cached snapshot,
            // which beats overwriting real data with an empty payload.
            throw DataSourceError.unavailable("Focus status access not granted")
        }

        let isOn = INFocusStatusCenter.default.focusStatus.isFocused ?? false
        return DataSnapshot(
            sourceID: descriptor.id,
            values: .object([
                "isOn": .bool(isOn),
                "status": .string(isOn ? "On" : "Off"),
            ])
        )
    }

    /// Prompts for Focus status access. The app's UI calls this once;
    /// fetch() never prompts, it only checks. Needs
    /// `NSFocusStatusUsageDescription` in Info.plist — iOS kills the process
    /// on the request without it.
    static func requestAccess() async -> Bool {
        await INFocusStatusCenter.default.requestAuthorization() == .authorized
    }

    /// Whether fetch() can succeed, for the UI's permission status.
    static var authorizationGranted: Bool {
        INFocusStatusCenter.default.authorizationStatus == .authorized
    }
}
