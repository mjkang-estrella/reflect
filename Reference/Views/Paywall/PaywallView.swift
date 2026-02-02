import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var subscriptionService: SubscriptionService

    let source: String

    @State private var billingPeriod: BillingPeriod = .yearly
    @State private var isLoadingProducts = false
    @State private var isPurchasing = false
    @State private var didLoadProducts = false
    @State private var errorMessage: String?
    @State private var animateIn = false
    @State private var didStartTrial = false
    @State private var didCompletePurchase = false
    @State private var didTrackDismiss = false

    init(source: String = "unknown") {
        self.source = source
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 24) {
                    topSection
                    benefitsSection
                    pricingSection
                    actionSection
                    footerSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 24)
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 12)
                .animation(.easeOut(duration: 0.35), value: animateIn)
            }

            Button {
                trackDismissIfNeeded()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(10)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .padding(.trailing, 20)
            .padding(.top, 16)
            .accessibilityLabel("Dismiss paywall")
        }
        .background(Color(.systemBackground))
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .task {
            await loadProductsIfNeeded()
        }
        .onAppear {
            AnalyticsService.track(.paywallViewed(source: source))
            animateIn = true
        }
        .onDisappear {
            trackDismissIfNeeded()
        }
        .alert(
            "Purchase Failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unable to complete purchase.")
        }
    }

    // MARK: - Sections

    private var topSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.orange, Color.pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Text("Unlock Your Full Journal")
                    .font(.title2.weight(.semibold))
                Text("Reflect deeper with AI-powered insights")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(benefits) { benefit in
                HStack(spacing: 12) {
                    Image(systemName: benefit.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundColor(.orange)
                        .background(
                            Circle().fill(Color.orange.opacity(0.12))
                        )

                    Text(benefit.text)
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Spacer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var pricingSection: some View {
        VStack(spacing: 16) {
            Picker("Billing", selection: $billingPeriod) {
                ForEach(BillingPeriod.allCases, id: \.self) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .disabled(monthlyProduct == nil || yearlyProduct == nil)

            VStack(spacing: 8) {
                if isLoadingProducts {
                    ProgressView()
                } else if let product = selectedProduct {
                    Text(priceTitle(for: product))
                        .font(.title2.weight(.semibold))

                    if billingPeriod == .yearly {
                        HStack(spacing: 8) {
                            if let monthlyEquivalent = monthlyEquivalentText(for: product) {
                                Text(monthlyEquivalent)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }

                            Text("Save 37%")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.orange)
                                )
                        }
                    }

                    if isTrialEligible {
                        Text("7-day free trial, then \(priceTitle(for: product))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(billingPeriod == .monthly ? "Billed monthly" : "Billed annually")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Pricing unavailable")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await purchaseSelectedProduct()
                }
            } label: {
                HStack(spacing: 8) {
                    if isProcessingPurchase {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(ctaTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.orange)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled((selectedProduct == nil && !isTrialEligible) || isProcessingPurchase)

            Button("Restore Purchases") {
                Task {
                    await restorePurchases()
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.secondary)
        }
    }

    private var footerSection: some View {
        VStack(spacing: 8) {
            Text("Cancel anytime.")
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                Button("Terms") {
                    openURL(termsURL)
                }
                Text("and")
                    .foregroundColor(.secondary)
                Button("Privacy Policy") {
                    openURL(privacyURL)
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .foregroundColor(.secondary)
    }

    // MARK: - Data

    private var monthlyProduct: Product? {
        subscriptionService.availableProducts.first { $0.id == monthlyProductID }
            ?? subscriptionService.availableProducts.first {
                $0.subscription?.subscriptionPeriod.unit == .month
            }
    }

    private var yearlyProduct: Product? {
        subscriptionService.availableProducts.first { $0.id == yearlyProductID }
            ?? subscriptionService.availableProducts.first {
                $0.subscription?.subscriptionPeriod.unit == .year
            }
    }

    private var selectedProduct: Product? {
        switch billingPeriod {
        case .monthly:
            return monthlyProduct
        case .yearly:
            return yearlyProduct
        }
    }

    private var isProcessingPurchase: Bool {
        isPurchasing || subscriptionService.purchaseInProgress
    }

    private var isTrialEligible: Bool {
        subscriptionService.isTrialEligible
    }

    private var ctaTitle: String {
        isTrialEligible ? "Start Free Trial" : "Subscribe Now"
    }

    private let monthlyProductID = "com.voicejournal.premium.monthly"
    private let yearlyProductID = "com.voicejournal.premium.yearly"

    private let benefits: [Benefit] = [
        Benefit(icon: "sparkles", text: "AI nudges while you record"),
        Benefit(icon: "calendar", text: "Smart prompts from your calendar"),
        Benefit(icon: "chart.line.uptrend.xyaxis", text: "Mood trends and insights"),
        Benefit(icon: "icloud", text: "Sync across all devices"),
        Benefit(icon: "infinity", text: "Unlimited journal entries"),
        Benefit(icon: "square.and.arrow.up", text: "Export to PDF"),
    ]

    private var termsURL: URL {
        URL(string: "https://example.com/terms")!
    }

    private var privacyURL: URL {
        URL(string: "https://example.com/privacy")!
    }

    // MARK: - Actions

    private func loadProductsIfNeeded() async {
        guard !didLoadProducts else { return }
        didLoadProducts = true
        isLoadingProducts = true
        do {
            try await subscriptionService.loadProducts()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingProducts = false
    }

    private func purchaseSelectedProduct() async {
        if subscriptionService.isTrialEligible {
            subscriptionService.startTrialIfEligible()
            didStartTrial = true
            dismiss()
            return
        }

        guard let product = selectedProduct else { return }

        isPurchasing = true
        AnalyticsService.track(.purchaseStarted(product: product.id, source: source))
        defer { isPurchasing = false }

        do {
            _ = try await subscriptionService.purchase(product)
            AnalyticsService.track(.purchaseCompleted(product: product.id, price: product.price))
            didCompletePurchase = true
            dismiss()
        } catch let error as SubscriptionError {
            switch error {
            case .userCancelled:
                AnalyticsService.track(.purchaseCancelled(product: product.id))
                return
            default:
                AnalyticsService.track(
                    .purchaseFailed(product: product.id, error: error.localizedDescription)
                )
                errorMessage = error.localizedDescription
            }
        } catch {
            AnalyticsService.track(
                .purchaseFailed(product: product.id, error: error.localizedDescription)
            )
            errorMessage = error.localizedDescription
        }
    }

    private func restorePurchases() async {
        AnalyticsService.track(.restorePurchasesTapped)
        let wasPremium = subscriptionService.isPremium
        do {
            try await subscriptionService.restorePurchases()
            let foundPurchase = subscriptionService.isPremium || wasPremium
            AnalyticsService.track(.restorePurchasesCompleted(foundPurchase: foundPurchase))
        } catch {
            AnalyticsService.track(
                .restorePurchasesCompleted(foundPurchase: subscriptionService.isPremium)
            )
            errorMessage = error.localizedDescription
        }
    }

    private func trackDismissIfNeeded() {
        guard !didTrackDismiss else { return }
        guard !didCompletePurchase && !didStartTrial else { return }
        AnalyticsService.track(.paywallDismissed(source: source))
        didTrackDismiss = true
    }

    private func priceTitle(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return product.displayPrice
        }

        let unit: String
        switch period.unit {
        case .month:
            unit = "month"
        case .year:
            unit = "year"
        case .week:
            unit = "week"
        case .day:
            unit = "day"
        @unknown default:
            unit = "period"
        }

        return "\(product.displayPrice) / \(unit)"
    }

    private func monthlyEquivalentText(for product: Product) -> String? {
        guard product.subscription?.subscriptionPeriod.unit == .year else { return nil }
        let monthly = product.price / Decimal(12)
        let formatted = monthly.formatted(product.priceFormatStyle)
        return "\(formatted) per month"
    }
}

private struct Benefit: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

private enum BillingPeriod: String, CaseIterable {
    case monthly
    case yearly

    var title: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    PaywallView()
        .environmentObject(SubscriptionService())
}
#endif
