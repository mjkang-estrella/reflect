import SwiftUI

enum AppGradientTheme: String, CaseIterable, Identifiable {
    case dusk
    case nightfall
    case rose

    var id: String { rawValue }

    var name: String {
        switch self {
        case .dusk:
            return "Dusk"
        case .nightfall:
            return "Nightfall"
        case .rose:
            return "Rose"
        }
    }

    var colors: [Color] {
        switch self {
        case .dusk:
            return [
                Color(red: 0.12, green: 0.14, blue: 0.26),
                Color(red: 0.23, green: 0.23, blue: 0.41),
                Color(red: 0.91, green: 0.65, blue: 0.62),
            ]
        case .nightfall:
            return [
                Color(hex: 0x1E2343),
                Color(hex: 0x3B3A68),
                Color(hex: 0xE8A69E),
            ]
        case .rose:
            return [
                Color(hex: 0x172233),
                Color(hex: 0x2F3A5F),
                Color(hex: 0xD9A3A7),
            ]
        }
    }
}

struct AppGradientBackground: View {
    @AppStorage("selectedGradientTheme") private var selectedTheme = AppGradientTheme.dusk.rawValue

    let opacity: Double

    init(opacity: Double = 1.0) {
        self.opacity = opacity
    }

    var body: some View {
        LinearGradient(
            colors: theme.colors,
            startPoint: .top,
            endPoint: .bottom
        )
        .opacity(opacity)
        .ignoresSafeArea()
    }

    private var theme: AppGradientTheme {
        AppGradientTheme(rawValue: selectedTheme) ?? .dusk
    }
}

struct GradientOptionCard: View {
    let theme: AppGradientTheme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LinearGradient(
                colors: theme.colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.9 : 0.3), lineWidth: isSelected ? 2 : 1)
            )

            HStack(spacing: 8) {
                Text(theme.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}
