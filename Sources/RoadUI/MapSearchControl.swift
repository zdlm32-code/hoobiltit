import SwiftUI

/// A magnifying-glass button that opens into the address field, and closes back into the
/// button.
///
/// Replaces `.searchable`. On current iOS that is a full-width bar along the bottom of the map
/// whenever the screen is up — over the part of the map nearest the car, for something used
/// occasionally — and hiding the navigation bar for drive mode no longer removed it. This is one
/// view whose width animates, so the button visibly becomes the field rather than being swapped
/// for it.
struct MapSearchControl: View {
    @Binding var text: String
    @Binding var isOpen: Bool
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if isOpen { submit() } else { open() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOpen ? "Search" : "Search an address")

            if isOpen {
                TextField("Search an address", text: $text)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit(submit)
                    // Focused once it exists: setting focus in the same transaction that
                    // inserts the field is dropped.
                    .task { isFocused = true }
                    .transition(.opacity)

                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .transition(.opacity)
                }

                Button("Cancel", action: close)
                    .font(.subheadline.weight(.medium))
                    .padding(.trailing, 14)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: isOpen ? .infinity : 44, alignment: .leading)
        .frame(height: 44)
        // A capsule as wide as it is tall is a circle, so one shape serves both states and the
        // change between them is a stretch rather than a cut.
        .background(.background.secondary, in: Capsule())
        .shadow(radius: 1, y: 1)
        // Dismissing the keyboard with nothing typed means the search was abandoned.
        .onChange(of: isFocused) { _, focused in
            if !focused, isOpen, text.trimmingCharacters(in: .whitespaces).isEmpty { close() }
        }
    }

    private func open() {
        withAnimation(.snappy(duration: 0.3)) { isOpen = true }
    }

    private func submit() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onSubmit()
        close()
    }

    private func close() {
        isFocused = false
        withAnimation(.snappy(duration: 0.3)) { isOpen = false }
    }
}
