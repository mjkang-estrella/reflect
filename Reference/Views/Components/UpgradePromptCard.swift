import SwiftUI

struct UpgradePromptCard: View {
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @State private var showingPaywall = false

    let icon: String
    let message: String
    let buttonTitle: String
    let analyticsFeature: String
    let paywallSource: String

    init(
        icon: String = "sparkles",
        message: String,
        buttonTitle: String = "Upgrade",
        analyticsFeature: String = "upgrade_prompt",
        paywallSource: String = "upgrade_prompt"
    ) {
        self.icon = icon
        self.message = message
        self.buttonTitle = buttonTitle
        self.analyticsFeature = analyticsFeature
        self.paywallSource = paywallSource
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.orange.opacity(0.15)))

            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()

            Button(buttonTitle) {
                AnalyticsService.track(.premiumFeatureBlocked(feature: analyticsFeature))
                showingPaywall = true
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.orange))
            .foregroundColor(.white)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: paywallSource)
                .environmentObject(subscriptionService)
        }
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    UpgradePromptCard(message: "Get AI nudges while you journal")
        .padding()
        .environmentObject(SubscriptionService())
}
#endif
