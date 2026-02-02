import SwiftUI

struct SkeletonCardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SkeletonLine(width: 120, height: 10)
                Spacer()
                SkeletonLine(width: 16, height: 10)
            }

            SkeletonLine(width: 180, height: 14)
            SkeletonLine(width: 220, height: 14)

            HStack(spacing: 8) {
                SkeletonCapsule(width: 50, height: 16)
                SkeletonCapsule(width: 60, height: 16)
                SkeletonCapsule(width: 42, height: 16)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .redacted(reason: .placeholder)
        .shimmer()
    }
}

struct SkeletonLine: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(Color(.systemFill))
            .frame(width: width, height: height)
    }
}

struct SkeletonCapsule: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Capsule()
            .fill(Color(.systemFill))
            .frame(width: width, height: height)
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.4),
                        Color.white.opacity(0.0),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .offset(x: phase * 220)
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 0.8
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}
