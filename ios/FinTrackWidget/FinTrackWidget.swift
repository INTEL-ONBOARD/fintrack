import SwiftUI
import WidgetKit

struct FinTrackWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSummarySnapshot
}

struct FinTrackWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FinTrackWidgetEntry {
        FinTrackWidgetEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (FinTrackWidgetEntry) -> Void) {
        completion(FinTrackWidgetEntry(date: .now, snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FinTrackWidgetEntry>) -> Void) {
        let entry = FinTrackWidgetEntry(date: .now, snapshot: WidgetSnapshotStore.load())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct FinTrackWidgetEntryView: View {
    let entry: FinTrackWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This month")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatted(entry.snapshot.expenseMinor, currency: entry.snapshot.currency))
                .font(.title3.bold())
            Text("spent")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let remaining = entry.snapshot.budgetRemainingMinor {
                Text("Budget left \(formatted(remaining, currency: entry.snapshot.currency))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private func formatted(_ minor: Int64, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        let amount = NSDecimalNumber(value: minor).dividing(by: NSDecimalNumber(value: 100))
        return formatter.string(from: amount) ?? "\(currency) \(minor)"
    }
}

struct FinTrackWidget: Widget {
    let kind = "FinTrackWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinTrackWidgetProvider()) { entry in
            FinTrackWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("FinTrack summary")
        .description("See this month's spending and remaining budget.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct FinTrackWidgetBundle: WidgetBundle {
    var body: some Widget {
        FinTrackWidget()
    }
}
