import SwiftUI

struct LimitReachedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @State private var showingPaywall = false

    let limit: Int
    let entryCount: Int
    let onManageEntries: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("You've reached your free limit")
                    .font(.title3.weight(.semibold))

                Text(
                    "Free accounts can store up to \(limit) journal entries. Upgrade to Premium for unlimited entries."
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                Text("\(min(entryCount, limit)) of \(limit) entries used")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)

                ProgressView(value: min(Double(entryCount), Double(limit)), total: Double(limit))
                    .tint(.orange)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            Button {
                AnalyticsService.track(
                    .premiumFeatureBlocked(feature: FeatureType.unlimitedEntries.rawValue)
                )
                showingPaywall = true
            } label: {
                Text("Upgrade to Premium")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button("Delete old entries") {
                AnalyticsService.track(
                    .premiumFeatureBlocked(feature: "unlimited_entries_manage")
                )
                onManageEntries()
                dismiss()
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.secondary)
        }
        .padding(24)
        .onAppear {
            AnalyticsService.track(
                .premiumFeatureBlocked(feature: FeatureType.unlimitedEntries.rawValue)
            )
        }
        .onChange(of: subscriptionService.hasUnlimitedEntries) { _, hasUnlimited in
            if hasUnlimited {
                dismiss()
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(source: "limit_reached")
                .environmentObject(subscriptionService)
        }
    }
}

#if DEBUG && !PREVIEWS_DISABLED
    #Preview {
        LimitReachedSheet(limit: 30, entryCount: 30, onManageEntries: {})
            .environmentObject(SubscriptionService())
            .padding()
    }
#endif
