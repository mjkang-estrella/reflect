import SwiftUI

struct MoodPickerView: View {
    @Binding var selectedMood: Mood?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Current mood display
                    if let mood = selectedMood {
                        currentMoodDisplay(mood)
                    }

                    // Mood grid
                    moodGrid
                }
                .padding()
            }
            .navigationTitle("How are you feeling?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if selectedMood != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear") {
                            selectedMood = nil
                            HapticManager.shared.impact(.light)
                            dismiss()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Current Mood Display

    private func currentMoodDisplay(_ mood: Mood) -> some View {
        VStack(spacing: 8) {
            Text(mood.emoji)
                .font(.system(size: 60))

            Text(mood.displayName)
                .font(.title2)
                .fontWeight(.semibold)

            Text("Selected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(mood.color.opacity(0.15))
        )
    }

    // MARK: - Mood Grid

    private var moodGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            ForEach(Mood.allCases, id: \.self) { mood in
                MoodButton(
                    mood: mood,
                    isSelected: selectedMood == mood
                ) {
                    selectedMood = mood
                    HapticManager.shared.impact(.medium)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Mood Button

struct MoodButton: View {
    let mood: Mood
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(mood.emoji)
                    .font(.system(size: 36))

                Text(mood.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? mood.color : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? mood.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Inline Mood Display

struct InlineMoodView: View {
    let mood: Mood?
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            if let mood = mood {
                HStack(spacing: 8) {
                    Text(mood.emoji)
                        .font(.title2)

                    Text(mood.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(mood.color.opacity(0.15))
                )
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "face.smiling")
                    Text("Add mood")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Compact Mood Picker (Horizontal Scroll)

struct CompactMoodPicker: View {
    @Binding var selectedMood: Mood?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Mood.allCases, id: \.self) { mood in
                    CompactMoodButton(
                        mood: mood,
                        isSelected: selectedMood == mood
                    ) {
                        if selectedMood == mood {
                            selectedMood = nil
                        } else {
                            selectedMood = mood
                        }
                        HapticManager.shared.impact(.light)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Compact Mood Button

struct CompactMoodButton: View {
    let mood: Mood
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(mood.emoji)
                    .font(.title2)

                Text(mood.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? mood.color : Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Inline Mood Button (for detail view)

struct InlineMoodButton: View {
    let mood: Mood
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(mood.emoji)
                    .font(.system(size: 28))

                Text(mood.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            .frame(width: 60)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? mood.color : Color(.tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? mood.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Mood Ring View (for displaying mood as a badge)

struct MoodRingView: View {
    let mood: Mood?
    var size: CGFloat = 32

    var body: some View {
        if let mood = mood {
            Text(mood.emoji)
                .font(.system(size: size * 0.6))
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(mood.color.opacity(0.2))
                )
        }
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    struct PreviewWrapper: View {
        @State private var selectedMood: Mood? = .happy

        var body: some View {
            VStack(spacing: 20) {
                InlineMoodView(mood: selectedMood) {}

                CompactMoodPicker(selectedMood: $selectedMood)

                MoodPickerView(selectedMood: $selectedMood)
            }
        }
    }

    return PreviewWrapper()
}
#endif
