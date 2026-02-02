import SwiftUI

struct LockedFeatureOverlay: ViewModifier {
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @State private var showingPaywall = false

    let isLocked: Bool
    let feature: String?

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(isLocked ? 0.45 : 1)

            if isLocked {
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .foregroundColor(.primary)

                    Text("Upgrade to unlock")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.primary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isLocked else { return }
            AnalyticsService.track(.premiumFeatureBlocked(feature: feature ?? "locked_feature"))
            showingPaywall = true
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: feature.map { "locked_\($0)" } ?? "locked_feature")
                .environmentObject(subscriptionService)
        }
    }
}

extension View {
    func lockedFeatureOverlay(isLocked: Bool, feature: String? = nil) -> some View {
        modifier(LockedFeatureOverlay(isLocked: isLocked, feature: feature))
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    VStack(spacing: 20) {
        Text("Locked content")
            .padding()
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            .lockedFeatureOverlay(isLocked: true)

        Text("Unlocked content")
            .padding()
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            .lockedFeatureOverlay(isLocked: false)
    }
    .padding()
    .environmentObject(SubscriptionService())
}
#endif
