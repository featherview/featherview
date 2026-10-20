import FeatherviewCore
import SwiftUI

/// In place of the cards and the preview while a batch runs (design "Running"): the settings in one line,
/// progress, time left and the image written last. No log list: Copy Log has it.
struct BatchRunView: View {
    let model: BatchModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.panelGap) {
            Text((BatchCard.core + BatchCard.extras.filter { $0.isAdded(in: model.settings) })
                .map { $0.summary(in: model.settings) }
                .joined(separator: " · "))
                .foregroundStyle(Theme.labelSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            ProgressView(value: Double(model.doneCount), total: Double(max(model.totalCount, 1))) {
                Text(model.isPaused ? "Paused · \(model.doneCount) of \(model.totalCount)"
                                    : "\(model.doneCount) of \(model.totalCount)")
                    .monospacedDigit()
            } currentValueLabel: {
                if let left = model.secondsLeft {
                    Text("About \(Duration.seconds(left.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))) left")
                }
            }
            BatchWrittenPreview(url: model.lastWritten)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Theme.panelPadding)
    }
}

/// Above the cards after a run (design "Done"): the run in one sentence, each failure by file name,
/// Show in Finder and Copy Log.
struct BatchDoneView: View {
    let model: BatchModel

    var body: some View {
        let failures = model.failures
        VStack(alignment: .leading, spacing: Theme.messagePadding) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.rowGap) {
                Image(systemName: failures.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                    .accessibilityHidden(true)
                Text(model.report ?? "")
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            if !failures.isEmpty {
                // Few failures show as they are; many scroll (lazily: a run can fail 10,000 files), so the
                // cards and the preview keep their room.
                if failures.count <= 5 {
                    lines(failures)
                } else {
                    ScrollView { lines(failures) }
                        .frame(height: Theme.batchPreviewMinHeight)
                }
            }
            HStack {
                Spacer()
                Button("Show in Finder") { model.showInFinder() }
                    .disabled(model.outputFolder == nil)
                Button("Copy Log") { model.copyLog() }
            }
        }
        .padding(Theme.rowPadding)
    }

    private func lines(_ failures: [String]) -> some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(Array(failures.enumerated()), id: \.offset) { _, line in
                Text(line).foregroundStyle(.red)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
