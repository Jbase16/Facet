import SwiftUI
import FacetCore

/// "Describe your widget" → on-device generation → an editable document.
/// The sheet's whole promise is honesty: it produces real layers, and when
/// Apple Intelligence can't run it says exactly why instead of spinning.
@available(iOS 26.0, *)
@MainActor
struct GenerateWidgetView: View {
    @Environment(\.dismiss) private var dismiss

    /// Called with the finished document; the gallery owns saving it.
    let onGenerated: (WidgetDocument) -> Void

    @State private var service = WidgetGeneratorService()
    @State private var prompt = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @FocusState private var promptFocused: Bool

    private static let examples = [
        "Minimal battery ring with percentage, dark, violet accent",
        "Sunny weather card: big temperature, condition, hourly line chart",
        "Steps dashboard with a progress bar and weekly bar chart",
    ]

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    switch WidgetGeneratorService.availability {
                    case .ready:
                        promptPanel
                        examplePanel
                        if let errorMessage {
                            errorCard(errorMessage)
                        }
                        generateButton
                        Text("Runs entirely on-device with Apple Intelligence. You get editable layers, not an image.")
                            .font(FacetUI.caption)
                            .foregroundStyle(FacetUI.inkTertiary)
                            .padding(.horizontal, 4)
                    case .unavailable(let reason):
                        unavailableCard(reason)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(FacetUI.bg)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(FacetToolButton())
                    .disabled(isGenerating)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isGenerating)
        .onAppear {
            service.prewarm()
            promptFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AI").facetEyebrow()
            Text("Generate Widget")
                .font(FacetUI.title(26))
                .kerning(-0.3)
                .foregroundStyle(FacetUI.ink)
        }
        .padding(.top, 8)
    }

    private var promptPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Describe your widget").facetEyebrow()
            TextField("", text: $prompt, axis: .vertical)
                .lineLimit(3...6)
                .font(FacetUI.label)
                .foregroundStyle(FacetUI.ink)
                .tint(FacetUI.accent)
                .focused($promptFocused)
                .padding(12)
                .background(FacetUI.raised)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(promptFocused ? FacetUI.hairlineStrong : FacetUI.hairline, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("A dark clock with the date and a moon icon…")
                            .font(FacetUI.label)
                            .foregroundStyle(FacetUI.inkTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .facetPanel()
    }

    private var examplePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try one").facetEyebrow()
                .padding(.horizontal, 4)
            ForEach(Self.examples, id: \.self) { example in
                Button {
                    prompt = example
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FacetUI.accent)
                            .padding(.top, 1)
                        Text(example)
                            .font(FacetUI.caption)
                            .foregroundStyle(FacetUI.inkSecondary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(FacetUI.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(FacetUI.hairline, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
            }
        }
    }

    private var generateButton: some View {
        Button(action: runGeneration) {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FacetUI.bg)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(isGenerating ? "Generating…" : "Generate")
                    .font(FacetUI.label)
            }
            .foregroundStyle(FacetUI.bg)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(trimmedPrompt.isEmpty ? FacetUI.accent.opacity(0.35) : FacetUI.accent)
            .clipShape(RoundedRectangle(cornerRadius: FacetUI.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(trimmedPrompt.isEmpty || isGenerating)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(FacetUI.sample)
            Text(message)
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.inkSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .facetPanel()
    }

    private func unavailableCard(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(FacetUI.inkTertiary)
                Text("Generation unavailable")
                    .font(FacetUI.label)
                    .foregroundStyle(FacetUI.ink)
            }
            Text(reason)
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.inkSecondary)
            Text("Widget generation runs on-device with Apple Intelligence — nothing you type leaves this device — so it needs Apple Intelligence to work.")
                .font(FacetUI.caption)
                .foregroundStyle(FacetUI.inkTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .facetPanel()
    }

    private func runGeneration() {
        guard !trimmedPrompt.isEmpty, !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        let description = trimmedPrompt
        Task {
            do {
                let document = try await service.generate(from: description)
                onGenerated(document)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}
