import SwiftData
import SwiftUI

struct TextEntrySheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title: String = ""
    @State private var bodyText: String = ""

    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Title (optional)", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 16, weight: .semibold))

                TextEditor(text: $bodyText)
                    .font(.system(size: 15))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(.separator).opacity(0.3))
                    )
            }
            .padding(20)
            .navigationTitle("New Text Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEntry()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveEntry() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle =
            trimmedTitle.isEmpty
            ? trimmedBody.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            : trimmedTitle

        let dataService = DataService(modelContext: modelContext)
        _ = dataService.createEntry(
            title: fallbackTitle,
            transcription: trimmedBody,
            duration: 0
        )
        try? dataService.save()

        onSave()
        dismiss()
    }
}

#if DEBUG && !PREVIEWS_DISABLED
    #Preview {
        TextEntrySheetView(onSave: {})
    }
#endif
