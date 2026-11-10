import SwiftUI

/// The coach screen: the real numbers first, then the coach's take, then a
/// conversation. Presented as a sheet. Builds its `CoachConversation` from the
/// app's API client; `CoachScreen` holds the layout so previews can drive it.
struct CoachView: View {
    @EnvironmentObject private var settings: AppSettings

    let today: TodayDTO
    let focus: CoachFocus
    let autoAsk: String?
    let onShowHistory: () -> Void

    @State private var conversation: CoachConversation?

    init(today: TodayDTO, focus: CoachFocus, autoAsk: String?, onShowHistory: @escaping () -> Void) {
        self.today = today
        self.focus = focus
        self.autoAsk = autoAsk
        self.onShowHistory = onShowHistory
    }

    var body: some View {
        Group {
            if let conversation {
                CoachScreen(
                    today: today, focus: focus, conversation: conversation,
                    autoAsk: autoAsk, onShowHistory: onShowHistory
                )
            } else {
                Palette.surface.ignoresSafeArea()
            }
        }
        .onAppear {
            guard conversation == nil else { return }
            let client = settings.makeClient()
            conversation = CoachConversation(today: today, focus: focus) { question, date, history in
                guard let client else { throw APIError.notConfigured }
                return try await client.ask(question: question, date: date, history: history).answer
            }
        }
    }
}

struct CoachScreen: View {
    let today: TodayDTO
    let focus: CoachFocus
    let conversation: CoachConversation
    let autoAsk: String?
    let onShowHistory: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var inputFocused = false
    @State private var didAutoAsk = false

    private static let bottomID = "coach-bottom"
    private static let countThreshold = 300

    private var model: CoachFocusModel { CoachFocusModel(focus: focus, today: today) }
    private var messages: [CoachMessage] { conversation.messages }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool {
        !trimmedDraft.isEmpty && !conversation.isPending && !conversation.isAtCap
            && draft.utf16.count <= CoachConversation.maxQuestionLength
    }

    private var isReadiness: Bool {
        if case .readiness = focus { return true }
        return false
    }

    /// Follow-ups under the latest finished answer, or suggestions when the
    /// screen was opened to "Ask something…". Questions already asked are skipped.
    private var chipQuestions: [String] {
        guard !conversation.isPending, !conversation.isAtCap else { return [] }
        if messages.isEmpty, autoAsk != nil { return [] }
        if let last = messages.last {
            guard last.role == .coach, last.state == .done else { return [] }
        }
        let candidates: [String]
        if messages.isEmpty {
            switch focus {
            case .readiness: candidates = CoachPrompts.suggestions(today)
            case .pillar: candidates = CoachPrompts.followUps(for: focus, decision: today.decision)
            }
        } else {
            candidates = CoachPrompts.followUps(for: focus, decision: today.decision)
        }
        let asked = Set(messages.filter { $0.role == .user }.map(\.text))
        return candidates.filter { !asked.contains($0) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    CoachFocusHeader(
                        model: model, decision: today.decision, isReadiness: isReadiness,
                        onShowHistory: onShowHistory, onClose: { dismiss() }
                    )
                    if !messages.isEmpty || !chipQuestions.isEmpty {
                        Hairline()
                    }
                    CoachThread(messages: messages) { Task { await conversation.retry() } }
                    if !chipQuestions.isEmpty {
                        CoachChips(questions: chipQuestions) { question in
                            Task { await conversation.ask(question) }
                        }
                        .transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.margin)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .animation(.easeInOut(duration: 0.25), value: chipQuestions)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .onChange(of: messages) { old, new in followMessages(old, new, proxy) }
            .onChange(of: chipQuestions) {
                // Chips under a fresh answer stay below its top; only the empty
                // state has nothing to protect.
                if messages.isEmpty { scrollToLatest(proxy) }
            }
            .onChange(of: inputFocused) { _, focused in
                if focused { scrollToLatest(proxy) }
            }
        }
        .sheetSurface()
        .presentationDragIndicator(.visible)
        .task { await start() }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 10) {
            if conversation.isAtCap {
                capped
            } else {
                inputRow
            }
            Text("AI-generated · explains today's call, can't change it")
                .font(.caption)
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(alignment: .top) {
            Palette.surface.overlay(alignment: .top) { Hairline() }.ignoresSafeArea(edges: .bottom)
        }
    }

    private var inputRow: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                CoachQuestionField(text: $draft, isFocused: $inputFocused, onSubmit: send, minLines: 1)
                    .overlay(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text("Ask a follow-up…")
                                .font(.body)
                                .foregroundStyle(Palette.textTertiary)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: Space.target)
                sendButton
            }
            .background(Palette.surfaceHi, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            if showsCount {
                Text("\(draft.utf16.count) / \(CoachConversation.maxQuestionLength)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(draft.utf16.count >= CoachConversation.maxQuestionLength ? Palette.warn : Palette.textTertiary)
                    .padding(.trailing, 8)
                    .accessibilityLabel("\(draft.utf16.count) of \(CoachConversation.maxQuestionLength) characters")
            }
        }
        .onChange(of: draft) { _, newValue in
            let limit = CoachConversation.maxQuestionLength
            if newValue.utf16.count > limit { draft = Self.clipped(newValue, utf16Limit: limit) }
        }
    }

    private var showsCount: Bool {
        draft.utf16.count >= CoachConversation.maxQuestionLength - Self.countThreshold
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.body.weight(.bold))
                .frame(width: Space.target - 8, height: Space.target - 8)
        }
        .buttonStyle(CoachSendStyle())
        .disabled(!canSend)
        .accessibilityLabel("Send")
    }

    private var capped: some View {
        Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .easeInOut(duration: 0.35)) {
                conversation.reset()
                draft = ""
            }
        } label: {
            Label("Start a new conversation", systemImage: "arrow.counterclockwise")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.canvas)
                .frame(maxWidth: .infinity, minHeight: Space.target)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func start() async {
        guard !didAutoAsk else { return }
        didAutoAsk = true
        if let autoAsk {
            await conversation.ask(autoAsk)
        } else {
            // Let the sheet finish presenting before raising the keyboard.
            try? await Task.sleep(for: .milliseconds(450))
            inputFocused = true
        }
    }

    private func send() {
        guard canSend else { return }
        let question = trimmedDraft
        draft = ""
        Task { await conversation.ask(question) }
    }

    /// New user/pending messages follow to the bottom; a finished coach answer
    /// is anchored at its top so the start of a long answer stays in view.
    private func followMessages(_ old: [CoachMessage], _ new: [CoachMessage], _ proxy: ScrollViewProxy) {
        if new.count > old.count { scrollToLatest(proxy); return }
        let before = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0.state) })
        if let finished = new.last(where: { $0.role == .coach && $0.state == .done && before[$0.id] != .done }) {
            if reduceMotion {
                proxy.scrollTo(finished.id, anchor: .top)
            } else {
                withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(finished.id, anchor: .top) }
            }
        } else if new != old {
            scrollToLatest(proxy)
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        }
    }

    /// The server counts UTF-16 units, so clip on those, at character boundaries.
    static func clipped(_ text: String, utf16Limit: Int) -> String {
        var used = 0
        var end = text.startIndex
        for index in text.indices {
            let units = text[index].utf16.count
            if used + units > utf16Limit { break }
            used += units
            end = text.index(after: index)
        }
        return String(text[..<end])
    }
}

/// Solid and bright once there is something to send, quiet before that.
private struct CoachSendStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Palette.canvas : Palette.textTertiary)
            .background(isEnabled ? Palette.accent : Palette.track, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.15), value: isEnabled)
            // The circle stays 36pt; the tappable area is the full target.
            .frame(width: Space.target, height: Space.target)
            .contentShape(Rectangle())
    }
}

// MARK: - Previews

#if DEBUG
private enum CoachPreviewData {
    static func baseline(_ today: Double?, _ normal: Double?, _ recent: [Double?], up: Bool, position: MetricPosition?) -> MetricBaselineDTO {
        MetricBaselineDTO(
            today: today, baseline30d: normal, neutralBand: nil, recent14d: recent,
            goodDirection: up ? "up" : "down", position: position
        )
    }

    static func today(decision: Decision = .recover, withBaselines: Bool = true) -> TodayDTO {
        let recovery = PillarScore(score: 9, drivers: [Driver(text: "HRV is well below your normal", detail: nil), Driver(text: "Resting heart rate is elevated", detail: nil)])
        let sleep = PillarScore(score: 64, drivers: [Driver(text: "Slept less than your usual", detail: nil)])
        let load = PillarScore(score: 71, drivers: [])
        let baselines = TodayBaselinesDTO(
            hrv: baseline(31, 56, [52, 55, 58, nil, 54, 49, 44, 41, 38, 40, 36, 34, 33, 31], up: true, position: .below),
            restingHr: baseline(66, 58, [57, 58, 58, 59, 58, 60, 61, 62, 63, 62, 64, 65, 66, 66], up: false, position: .above),
            sleepHours: baseline(6.1, 7.2, [7.4, 7.0, 7.3, 6.9, 7.1, 6.5, 6.2, 7.0, 7.2, 6.8, 6.4, 6.0, 6.3, 6.1], up: true, position: .below),
            load7d: baseline(11.2, 9.4, [8, 9, 10, 9, 11, 12, 10, 9, 8, 10, 11, 12, 11, 11.2], up: false, position: .above)
        )
        return TodayDTO(
            date: "2026-11-09", readiness: 41, decision: decision, calibrating: false,
            pillars: Pillars(sleep: sleep, recovery: recovery, load: load),
            overridesApplied: [], confidence: "high", missing: [], sleepPending: nil,
            advisor: AdvisorNote(decision: decision, why: [], prescription: "", ifIgnored: "", source: "template"),
            baselines: withBaselines ? baselines : nil
        )
    }

    static let answer = "Your HRV is 31 ms against a normal of 56, and your resting heart rate is up 8 bpm. Together that is a body still catching up from the last few days, so recovery is the priority today.\n\nLocked decision: Recover. The coach explains this call; it can't change it."

    @MainActor static func conversation(
        _ today: TodayDTO, _ focus: CoachFocus, failing: Bool = false
    ) -> CoachConversation {
        CoachConversation(today: today, focus: focus) { _, _, _ in
            try await Task.sleep(for: .milliseconds(900))
            if failing { throw APIError.notConfigured }
            return answer
        }
    }
}

private struct CoachPreviewHost: View {
    let today: TodayDTO
    let focus: CoachFocus
    var autoAsk: String?
    var failing = false
    var prefill = 0
    @State private var conversation: CoachConversation

    init(today: TodayDTO, focus: CoachFocus, autoAsk: String? = nil, failing: Bool = false, prefill: Int = 0) {
        self.today = today
        self.focus = focus
        self.autoAsk = autoAsk
        self.failing = failing
        self.prefill = prefill
        _conversation = State(initialValue: CoachPreviewData.conversation(today, focus, failing: failing))
    }

    var body: some View {
        CoachScreen(today: today, focus: focus, conversation: conversation, autoAsk: autoAsk, onShowHistory: {})
            .task {
                for index in 0..<prefill { await conversation.ask("Question \(index + 1)") }
            }
    }
}

#Preview("Recovery with baselines") {
    let today = CoachPreviewData.today()
    CoachPreviewHost(today: today, focus: .pillar(.recovery), autoAsk: CoachPrompts.autoQuestion(for: .pillar(.recovery), today: today))
}

#Preview("Sleep with baselines") {
    let today = CoachPreviewData.today()
    CoachPreviewHost(today: today, focus: .pillar(.sleep), autoAsk: CoachPrompts.autoQuestion(for: .pillar(.sleep), today: today))
}

#Preview("Readiness, Ask something") {
    CoachPreviewHost(today: CoachPreviewData.today(), focus: .readiness)
}

#Preview("Recovery, no baselines") {
    let today = CoachPreviewData.today(withBaselines: false)
    CoachPreviewHost(today: today, focus: .pillar(.recovery), autoAsk: CoachPrompts.autoQuestion(for: .pillar(.recovery), today: today))
}

#Preview("Failed message") {
    let today = CoachPreviewData.today()
    CoachPreviewHost(today: today, focus: .readiness, autoAsk: CoachPrompts.autoQuestion(for: .readiness, today: today), failing: true)
}

#Preview("At the cap") {
    CoachPreviewHost(today: CoachPreviewData.today(), focus: .readiness, prefill: 10)
}

#Preview("Large type") {
    let today = CoachPreviewData.today()
    CoachPreviewHost(today: today, focus: .pillar(.recovery), autoAsk: CoachPrompts.autoQuestion(for: .pillar(.recovery), today: today))
        .dynamicTypeSize(.accessibility3)
}
#endif
