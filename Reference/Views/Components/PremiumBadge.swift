import SwiftUI

struct PremiumBadge: View {
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @State private var showingPaywall = false

    var text: String = "PRO"
    var showsIcon: Bool = true
    var isInteractive: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            if showsIcon {
                Image(systemName: "crown.fill")
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundColor(.white)
        .background(Capsule().fill(Color.orange))
        .contentShape(Capsule())
        .allowsHitTesting(isInteractive)
        .onTapGesture {
            guard isInteractive else { return }
            AnalyticsService.track(.premiumFeatureBlocked(feature: "premium_badge"))
            showingPaywall = true
        }
        .accessibilityLabel("Premium feature")
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "premium_badge")
                .environmentObject(subscriptionService)
        }
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    PremiumBadge()
        .environmentObject(SubscriptionService())
}
#endif
