import Foundation
import FoundationModels
import FacetCore

/// On-device widget generation via Apple's FoundationModels. The model's
/// only job is to fill in a WidgetDraft (guided generation guarantees the
/// shape); DraftMapper guarantees the rest. Nothing leaves the device.
@available(iOS 26.0, *)
@MainActor
@Observable
final class WidgetGeneratorService {

    enum Availability: Equatable {
        case ready
        /// User-readable reason. Shown verbatim — being honest about why
        /// generation is off beats a dead button.
        case unavailable(String)
    }

    static var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.deviceNotEligible):
            return .unavailable("This device doesn't support Apple Intelligence, which powers widget generation.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Apple Intelligence is turned off. Enable it in Settings › Apple Intelligence & Siri, then come back.")
        case .unavailable(.modelNotReady):
            return .unavailable("The on-device model is still downloading. Try again in a few minutes.")
        case .unavailable:
            return .unavailable("Apple Intelligence isn't available right now, and widget generation needs it.")
        }
    }

    struct GenerationFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Kept across prewarm → generate so the prewarmed state is actually
    /// used; cleared after each generation because a fresh session (no
    /// transcript) keeps repeated attempts independent.
    private var session: LanguageModelSession?

    /// Load the model before the user finishes typing — first-token latency
    /// is the whole difference between "instant" and "broken".
    func prewarm() {
        guard Self.availability == .ready, session == nil else { return }
        let session = makeSession()
        session.prewarm()
        self.session = session
    }

    func generate(from description: String) async throws -> WidgetDocument {
        if case .unavailable(let reason) = Self.availability {
            throw GenerationFailure(message: reason)
        }
        let session = self.session ?? makeSession()
        self.session = nil
        do {
            let response = try await session.respond(
                to: "Design this widget: \(description)",
                generating: WidgetDraft.self
            )
            return DraftMapper.document(from: response.content)
        } catch let error as LanguageModelSession.GenerationError {
            throw GenerationFailure(message: Self.message(for: error))
        } catch {
            throw GenerationFailure(message: "Generation failed: \(error.localizedDescription)")
        }
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: Self.instructions)
    }

    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            "That description is too long for the on-device model. Try a shorter one."
        case .guardrailViolation, .refusal:
            "The on-device model declined that description. Try rephrasing it."
        case .decodingFailure:
            "The model produced an unusable design. Try again, or reword the description."
        case .rateLimited:
            "Generation is temporarily rate-limited. Wait a moment and try again."
        case .concurrentRequests:
            "A generation is already in progress."
        case .assetsUnavailable:
            "The on-device model isn't loaded right now. Try again in a few minutes."
        case .unsupportedLanguageOrLocale:
            "The on-device model doesn't support this language yet. Try describing the widget in English."
        default:
            "Generation failed. Try again, or reword the description."
        }
    }

    /// Task + hard constraints. The schema (via @Generable guides) teaches
    /// the field-level details; instructions carry the design sensibility
    /// the schema can't express. Kept tight — on-device context is small.
    private static let instructions = """
    You design iOS home-screen widgets as a small set of layers on a square canvas.

    Coordinates are normalized 0-1 on both axes; (0, 0) is the top-left and every layer's \
    x/y is its CENTER, so a full-width title row near the top is x 0.5, y 0.15. Keep layers \
    inside the canvas and don't overlap text with text.

    Rules:
    - Use 2 to 6 layers. One clear hero element (a big number, ring, or symbol), small \
    supporting captions. Whitespace is good.
    - Colors must have strong contrast against the background. Use one accent color; \
    keep the rest neutral. Honor any colors or mood the request names.
    - Only reference the data paths listed in the field descriptions — never invent paths.
    - Text templates mix literal text with {expression} spans. Gauge values are bare \
    expressions that stay within 0-1.
    - A clock is text like '{pad(time.hour, 2)}:{pad(time.minute, 2)}'; a date is \
    '{time.weekdayName}, {time.monthName} {time.day}'.
    - Match the request. Don't add data the user didn't ask for.
    """
}
