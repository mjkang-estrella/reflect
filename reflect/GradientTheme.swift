import SwiftUI

enum AppGradientTheme: String, CaseIterable, Identifiable {
    case dusk
    case morning
    case afternoon
    case evening

    var id: String { rawValue }

    var name: String {
        switch self {
        case .dusk:
            return "Default"
        case .morning:
            return "Morning"
        case .afternoon:
            return "Afternoon"
        case .evening:
            return "Evening"
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
        case .morning:
            return [
                Color(hex: 0xFFEDD5),
                Color(hex: 0xFCD34D),
                Color(hex: 0xFDBA74),
            ]
        case .afternoon:
            return [
                Color(hex: 0xBFDBFE),
                Color(hex: 0x60A5FA),
                Color(hex: 0x2563EB),
            ]
        case .evening:
            return [
                Color(hex: 0x312E81),
                Color(hex: 0x7C3AED),
                Color(hex: 0xF97316),
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
