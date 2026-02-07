import SwiftUI

struct ChatModeView: View {
    @Binding var isPresented: Bool
    @State private var isVisible = false

    private let transitionDuration: Double = 0.6

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isVisible ? 1 : 0)

            Color.black
                .opacity(isVisible ? 0.22 : 0)

            ChatView(backgroundOpacity: 0.9, onDismiss: requestDismiss)
                .scaleEffect(isVisible ? 1 : 0.98)
                .opacity(isVisible ? 1 : 0)
        }
        .ignoresSafeArea()
        .presentationBackground(.clear)
        .interactiveDismissDisabled(true)
        .onAppear {
            withAnimation(.easeInOut(duration: transitionDuration)) {
                isVisible = true
            }
        }
    }

    private func requestDismiss() {
        withAnimation(.easeInOut(duration: transitionDuration)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + transitionDuration) {
            isPresented = false
        }
    }
}

#if DEBUG && !PREVIEWS_DISABLED
    #Preview {
        ChatModeView(isPresented: .constant(true))
            .environmentObject(AuthStore())
    }
#endif
