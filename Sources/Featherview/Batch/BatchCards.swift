import FeatherviewCore
import SwiftUI

/// The batch settings (design "Cards"): Format, Size and Name always, the added steps after them in the
/// Add Step menu's order; one card open at a time, the others folded to their summary.
/// One grouped form, a card per section: it scrolls by itself (a form inside a scroll view collapses).
struct BatchCards: View {
    @Bindable var model: BatchModel

    var body: some View {
        Form {
            ForEach(BatchCard.core + BatchCard.extras.filter { $0.isAdded(in: model.settings) }) { card in
                Section { BatchCardRows(card: card, model: model) }
            }
            Section {
                Menu("Add Step") {
                    ForEach(BatchCard.extras) { card in
                        Button(card.title) {
                            card.setAdded(true, in: &model.settings)
                            model.openCard = card
                        }
                        .disabled(card.isAdded(in: model.settings))
                    }
                }
                .fixedSize()
            }
        }
        .formStyle(.grouped)
    }
}

/// A card's header row and, when open, its settings rows.
private struct BatchCardRows: View {
    let card: BatchCard
    @Bindable var model: BatchModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOpen: Bool { model.openCard == card }

    var body: some View {
        HStack(spacing: Theme.rowGap) {
            Button(action: toggle) {
                HStack(spacing: Theme.rowGap) {
                    if let number = card.number {
                        Text(verbatim: "\(number)")
                            .font(Theme.badge)
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                            .frame(width: Theme.batchCardNumber, height: Theme.batchCardNumber)
                            .overlay(Circle().strokeBorder(Theme.accent))
                            .accessibilityHidden(true)
                    }
                    Image(systemName: "chevron.forward")
                        .font(Theme.hint.weight(.semibold))
                        .foregroundStyle(Theme.labelSecondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .accessibilityHidden(true)
                    Text(card.title)
                        .font(Theme.panelHeader)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: Theme.rowGap)
                    if !isOpen {
                        Text(card.summary(in: model.settings))
                            .foregroundStyle(Theme.labelSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOpen ? .isSelected : [])
            if card.number == nil {
                Button {
                    if isOpen { model.openCard = nil }
                    card.setAdded(false, in: &model.settings)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Theme.labelSecondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Remove \(Text(card.title))", comment: "Batch card: removes an added step"))
            }
        }
        if isOpen { BatchCardBody(card: card, model: model) }
    }

    private func toggle() {
        withAnimation(Theme.Motion.moving(Theme.Motion.panel, reduceMotion: reduceMotion)) {
            model.openCard = isOpen ? nil : card
        }
    }
}
