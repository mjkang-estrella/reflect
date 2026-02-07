import SwiftUI

struct ChatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authStore: AuthStore

    let backgroundOpacity: Double
    let onDismiss: (() -> Void)?

    private let chatBottomID = "chat-bottom"

    @StateObject private var viewModel = ChatViewModel()
    @State private var showDiscardConfirmation = false
    @State private var savedEntry: JournalEntry?
    @FocusState private var isComposerFocused: Bool

    init(backgroundOpacity: Double = 1.0, onDismiss: (() -> Void)? = nil) {
        self.backgroundOpacity = backgroundOpacity
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppGradientBackground(opacity: backgroundOpacity)
                Color.black.opacity(0.1).ignoresSafeArea()

                VStack(spacing: 12) {
                    headerRow
                        .padding(.top, 14)
                        .padding(.horizontal, 16)

                    chatThread
                        .padding(.horizontal, 16)

                    composerBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $savedEntry) { entry in
                JournalSummaryView(entry: entry, onClose: {
                    performDismiss()
                })
            }
            .alert("Discard chat?", isPresented: $showDiscardConfirmation) {
                Button("Keep", role: .cancel) {}
                Button("Discard", role: .destructive) {
                    Task {
                        await viewModel.discardDraftIfNeeded()
                        performDismiss()
                    }
                }
            } message: {
                Text("Your unsaved chat will be lost.")
            }
            .alert("Chat Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .onDisappear {
                viewModel.cleanupOnDisappear()
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Button(action: handleCloseTap) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: 0x111827))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Chat Reflection")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isListening ? Color(hex: 0xFB2C36) : Color(hex: 0x86EFAC))
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.82))
                }
            }

            Spacer(minLength: 12)

            Button(action: saveSession) {
                if viewModel.isSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color(hex: 0x111827))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white))
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(viewModel.canSave ? .white : Color(hex: 0x6B7280))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(viewModel.canSave ? Color(hex: 0x22C55E) : Color.white)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSave || viewModel.isSaving)
        }
    }

    private var chatThread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Today")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: 0x4B5563))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.78)))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 2)

                    ForEach(viewModel.messages) { message in
                        messageBubble(for: message)
                    }

                    if viewModel.messages.isEmpty {
                        MessengerEmptyState()
                            .padding(.top, 10)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(chatBottomID)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
            }
            .onAppear {
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: viewModel.messages.count) { _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
        }
        .frame(maxHeight: .infinity)
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                Task {
                    await viewModel.toggleDictation()
                }
            } label: {
                Image(systemName: viewModel.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(viewModel.isListening ? Color(hex: 0xFB2C36) : Color(hex: 0x0F1115))
                    )
            }
            .buttonStyle(.plain)

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white)

                TextField("Type a message", text: singleLineDraftBinding)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: 0x111827))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .focused($isComposerFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        sendDraft()
                    }
            }
            .frame(height: 48)

            Button {
                sendDraft()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(viewModel.canSend ? Color(hex: 0x22C55E) : Color(hex: 0x9CA3AF))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSend)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.22))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                )
        )
    }

    private var statusText: String {
        if viewModel.isSaving {
            return "Saving..."
        }
        if viewModel.isListening {
            return "Listening"
        }
        return viewModel.messages.isEmpty ? "Ready to chat" : "Active"
    }

    private var latestAssistantMessageID: UUID? {
        viewModel.messages.last(where: { $0.role == .assistant })?.id
    }

    private var singleLineDraftBinding: Binding<String> {
        Binding(
            get: {
                viewModel.draftText.replacingOccurrences(of: "\n", with: " ")
            },
            set: { newValue in
                viewModel.draftText = newValue.replacingOccurrences(of: "\n", with: " ")
            }
        )
    }

    private func refreshCurrentFollowUp() {
        Task {
            await viewModel.refreshQuestion()
        }
    }

    private func messageBubble(for message: ChatMessage) -> some View {
        let isCurrentFollowUp = latestAssistantMessageID == message.id
        let refreshAction: (() -> Void)? = isCurrentFollowUp ? { refreshCurrentFollowUp() } : nil
        return MessengerBubble(
            message: message,
            isCurrentFollowUp: isCurrentFollowUp,
            followUpStatus: isCurrentFollowUp ? viewModel.currentQuestion?.status : nil,
            onRefresh: refreshAction
        )
    }

    private func sendDraft() {
        guard let userId = authStore.userId, let userUUID = UUID(uuidString: userId) else {
            return
        }

        Task {
            await viewModel.sendDraft(userId: userUUID)
            isComposerFocused = false
        }
    }

    private func saveSession() {
        guard let userId = authStore.userId, let userUUID = UUID(uuidString: userId) else {
            return
        }

        Task {
            if let entry = await viewModel.saveSession(userId: userUUID) {
                savedEntry = entry
            }
        }
    }

    private func handleCloseTap() {
        if viewModel.hasUnsavedContent {
            showDiscardConfirmation = true
        } else {
            performDismiss()
        }
    }

    private func performDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(chatBottomID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(chatBottomID, anchor: .bottom)
            }
        }
    }
}

private struct MessengerBubble: View {
    let message: ChatMessage
    let isCurrentFollowUp: Bool
    let followUpStatus: QuestionStatus?
    let onRefresh: (() -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .assistant {
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(hex: 0x6E11B0))
                    )
                bubbleView
                Spacer(minLength: 26)
            } else {
                Spacer(minLength: 26)
                bubbleView
            }
        }
    }

    private var bubbleView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.role == .assistant, isCurrentFollowUp {
                followUpStatusRow
            }

            Text(message.text)
                .font(
                    message.role == .assistant
                        ? .system(size: 16, weight: .regular, design: .serif)
                        : .system(size: 15, weight: .regular)
                )
                .foregroundColor(message.role == .assistant ? Color(hex: 0x111827) : .white)
                .fixedSize(horizontal: false, vertical: true)

            Text(Self.timeFormatter.string(from: message.createdAt))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(
                    message.role == .assistant
                        ? Color(hex: 0x6B7280)
                        : Color.white.opacity(0.78)
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: UIScreen.main.bounds.width * 0.68, alignment: .leading)
        .background(bubbleShape.fill(bubbleColor))
    }

    @ViewBuilder
    private var followUpStatusRow: some View {
        HStack(spacing: 8) {
            Text("AI FOLLOW-UP")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: 0x6E11B0))
                .tracking(0.6)

            Spacer(minLength: 6)

            if followUpStatus == .pendingValidation {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color(hex: 0x6E11B0))
                    .frame(width: 16, height: 16)
            } else if followUpStatus == .answered {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: 0x22C55E))
                    .frame(width: 16, height: 16)
            } else if let onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: 0x6B7280))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bubbleColor: Color {
        message.role == .assistant ? Color.white : Color(hex: 0x0F1115)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        if message.role == .assistant {
            return UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: 8, bottomLeading: 18, bottomTrailing: 18, topTrailing: 18),
                style: .continuous
            )
        }
        return UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: 18, bottomLeading: 18, bottomTrailing: 8, topTrailing: 18),
            style: .continuous
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

private struct MessengerEmptyState: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: 0x6E11B0))
                )
            Text("how was your day?")
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundColor(Color(hex: 0x1F2937))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(topLeading: 8, bottomLeading: 18, bottomTrailing: 18, topTrailing: 18),
                        style: .continuous
                    )
                    .fill(Color.white)
                )
                .frame(maxWidth: UIScreen.main.bounds.width * 0.68, alignment: .leading)
            Spacer(minLength: 26)
        }
    }
}

#if DEBUG && !PREVIEWS_DISABLED
    #Preview {
        ChatView()
            .environmentObject(AuthStore())
    }
#endif
