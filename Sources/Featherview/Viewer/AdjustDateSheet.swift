import FeatherviewCore
import SwiftUI

/// Image › Adjust Date Taken…: the original date taken and a picker for the new one (wall times, so GMT throughout).
struct AdjustDateSheet: View {
    let model: ViewerModel
    let sheet: ViewerModel.DateSheetState
    @State private var adjusted: Date

    init(model: ViewerModel, sheet: ViewerModel.DateSheetState) {
        self.model = model
        self.sheet = sheet
        // shortcut: a file without any readable date starts at now's UTC wall time, read the local one if anyone notices.
        _adjusted = State(initialValue: sheet.current.flatMap(DateTaken.wallTime) ?? .now)
    }

    private static let style = Date.FormatStyle(date: .abbreviated, time: .standard, timeZone: TimeZone(secondsFromGMT: 0)!)

    private func formatted(_ exif: String?) -> String {
        exif.flatMap(DateTaken.wallTime)?.formatted(Self.style) ?? exif ?? ""
    }

    private var unchanged: Bool { sheet.current == DateTaken.exif(adjusted) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adjust Date Taken").font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Original").gridColumnAlignment(.trailing)
                    VStack(alignment: .leading) {
                        if let original = sheet.original {
                            Text(formatted(original))
                        } else {
                            Text("None, file date \(formatted(sheet.fileDate))")
                        }
                        if !sheet.others.isEmpty {
                            Text("and \(sheet.others.count) more").foregroundStyle(.secondary)
                        }
                    }
                }
                GridRow {
                    Text("Adjusted")
                    SecondsDatePicker(date: $adjusted).accessibilityLabel("Adjusted")
                }
            }
            Text("The file's date changes too.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.dateSheet = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Adjust") { model.adjustDateTaken(to: DateTaken.exif(adjusted)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(unchanged)
            }
        }
        .padding()
    }
}

/// Date and time with seconds, in GMT: SwiftUI's DatePicker has no seconds on macOS.
private struct SecondsDatePicker: NSViewRepresentable {
    @Binding var date: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinuteSecond]
        picker.timeZone = TimeZone(secondsFromGMT: 0)
        // The years EXIF can hold.
        picker.minDate = DateTaken.wallTime("0001:01:01 00:00:00")
        picker.maxDate = DateTaken.wallTime("9999:12:31 23:59:59")
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.date = $date
        if picker.dateValue != date { picker.dateValue = date }
    }

    func makeCoordinator() -> Coordinator { Coordinator(date: $date) }

    @MainActor final class Coordinator: NSObject {
        var date: Binding<Date>
        init(date: Binding<Date>) { self.date = date }
        @objc func changed(_ picker: NSDatePicker) { date.wrappedValue = picker.dateValue }
    }
}
