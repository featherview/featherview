import FeatherviewCore
import SwiftUI

/// Replaces the steps and detail columns while a batch runs: progress, time left, the log.
struct BatchRunView: View {
    let model: BatchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: Double(model.doneCount), total: Double(max(model.totalCount, 1))) {
                Text(model.isPaused ? "Paused · \(model.doneCount) of \(model.totalCount)"
                                    : "\(model.doneCount) of \(model.totalCount)")
                    .monospacedDigit()
            } currentValueLabel: {
                if let left = model.secondsLeft {
                    Text("About \(Duration.seconds(left.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))) left")
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(model.results.enumerated()), id: \.offset) { index, result in
                            Text(result.logLine)
                                .foregroundStyle(result.status == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                                .id(index)
                        }
                    }
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onChange(of: model.results.count) { _, count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
            HStack {
                Spacer()
                Button("Copy Log") { model.copyLog() }
                    .disabled(model.results.isEmpty)
            }
        }
        .padding()
    }
}

/// After a run: the summary line at the top, until the settings change or Start is pressed again.
struct BatchSummaryBar: View {
    let model: BatchModel

    var body: some View {
        HStack {
            Image(systemName: model.results.contains { $0.status != .converted } ? "exclamationmark.triangle" : "checkmark.circle")
            Text(model.summaryLine)
            Spacer()
            Button("Copy Log") { model.copyLog() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
