import SwiftUI

struct PremiumFeatureButton<Label: View>: View {
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @State private var showingPaywall = false

    let feature: FeatureType
    let action: () -> Void
    let label: () -> Label

    init(
        feature: FeatureType,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.feature = feature
        self.action = action
        self.label = label
    }

    var body: some View {
        Button {
            if feature.isEntitled(using: subscriptionService) {
                action()
            } else {
                AnalyticsService.track(.premiumFeatureBlocked(feature: feature.rawValue))
                showingPaywall = true
            }
        } label: {
            label()
                .overlay(alignment: .topTrailing) {
                    if feature.isPremiumOnly {
                        PremiumBadge(isInteractive: false)
                            .offset(x: 6, y: -6)
                    }
                }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "feature_\(feature.rawValue)")
                .environmentObject(subscriptionService)
        }
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    PremiumFeatureButton(feature: .insights, action: {}) {
        Text("Open Insights")
            .padding()
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
    .padding()
    .environmentObject(SubscriptionService())
}
#endif
