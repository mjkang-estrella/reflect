import SwiftUI
import SwiftData

struct TagPickerView: View {
    @Binding var selectedTags: [String]
    @Query(sort: \Tag.name) private var availableTags: [Tag]
    @Environment(\.modelContext) private var modelContext

    @State private var newTagName: String = ""
    @State private var showingNewTagSheet = false
    @State private var selectedColor: String = "#007AFF"

    private let colorOptions = [
        "#007AFF", // Blue
        "#34C759", // Green
        "#FF9500", // Orange
        "#FF3B30", // Red
        "#AF52DE", // Purple
        "#FF2D55", // Pink
        "#5856D6", // Indigo
        "#00C7BE", // Teal
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Selected tags
            if !selectedTags.isEmpty {
                selectedTagsSection
            }

            // Available tags
            availableTagsSection

            // Add new tag button
            addTagButton
        }
        .sheet(isPresented: $showingNewTagSheet) {
            newTagSheet
        }
    }

    // MARK: - Selected Tags Section

    private var selectedTagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(selectedTags, id: \.self) { tagName in
                    TagChip(
                        name: tagName,
                        color: colorForTag(tagName),
                        isSelected: true
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTags.removeAll { $0 == tagName }
                        }
                        HapticManager.shared.impact(.light)
                    }
                }
            }
        }
    }

    // MARK: - Available Tags Section

    private var availableTagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available Tags")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            if unselectedTags.isEmpty && availableTags.isEmpty {
                Text("No tags yet. Create your first tag!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(unselectedTags, id: \.id) { tag in
                        TagChip(
                            name: tag.name,
                            color: tag.color,
                            isSelected: false
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTags.append(tag.name)
                            }
                            HapticManager.shared.impact(.light)
                        }
                    }
                }
            }
        }
    }

    private var unselectedTags: [Tag] {
        availableTags.filter { !selectedTags.contains($0.name) }
    }

    // MARK: - Add Tag Button

    private var addTagButton: some View {
        Button(action: {
            showingNewTagSheet = true
        }) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text("New Tag")
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.accentColor)
        }
        .padding(.top, 4)
    }

    // MARK: - New Tag Sheet

    private var newTagSheet: some View {
        NavigationStack {
            Form {
                Section("Tag Name") {
                    TextField("Enter tag name", text: $newTagName)
                        .autocorrectionDisabled()
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(colorOptions, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                    HapticManager.shared.selection()
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("New Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingNewTagSheet = false
                        resetNewTagForm()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        createTag()
                    }
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helper Methods

    private func colorForTag(_ name: String) -> Color {
        if let tag = availableTags.first(where: { $0.name == name }) {
            return tag.color
        }
        return .accentColor
    }

    private func createTag() {
        let trimmedName = newTagName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // Check if tag already exists
        guard !availableTags.contains(where: { $0.name.lowercased() == trimmedName.lowercased() }) else {
            return
        }

        let newTag = Tag(name: trimmedName, colorHex: selectedColor)
        modelContext.insert(newTag)

        // Add to selected tags
        selectedTags.append(trimmedName)

        showingNewTagSheet = false
        resetNewTagForm()
        HapticManager.shared.notification(.success)
    }

    private func resetNewTagForm() {
        newTagName = ""
        selectedColor = "#007AFF"
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let name: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if isSelected {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? color : color.opacity(0.15))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Inline Tag Display

struct InlineTagsView: View {
    let tags: [String]
    var onTap: (() -> Void)? = nil

    var body: some View {
        if tags.isEmpty {
            Button(action: { onTap?() }) {
                HStack(spacing: 4) {
                    Image(systemName: "tag")
                    Text("Add tags")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.1))
                        )
                }
            }
            .onTapGesture {
                onTap?()
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, spacing: spacing, subviews: subviews)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, spacing: spacing, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            let point = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var positions: [CGPoint] = []
        var height: CGFloat = 0

        init(in maxWidth: CGFloat, spacing: CGFloat, subviews: Subviews) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }

            height = currentY + lineHeight
        }
    }
}

#if DEBUG && !PREVIEWS_DISABLED
#Preview {
    struct PreviewWrapper: View {
        @State private var selectedTags: [String] = ["Personal", "Work"]

        var body: some View {
            TagPickerView(selectedTags: $selectedTags)
                .padding()
        }
    }

    return PreviewWrapper()
}
#endif
