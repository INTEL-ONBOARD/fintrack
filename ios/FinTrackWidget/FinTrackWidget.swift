import SwiftUI
import WidgetKit

struct FinTrackWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSummarySnapshot?
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
    @Environment(\.widgetFamily) private var family
    let entry: FinTrackWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("FINTRACK")
                    .font(.caption2.weight(.bold))
                    .tracking(1.3)
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 0)
            if let snapshot = entry.snapshot {
                Text("This month")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                Text(formatted(snapshot.expenseMinor, currency: snapshot.currency))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if family == .systemMedium {
                    Text("spent")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                if let remaining = snapshot.budgetRemainingMinor {
                    Text("Budget left \(formatted(remaining, currency: snapshot.currency))")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.22, green: 0.68, blue: 0.34))
                }
            } else {
                Text("Spending unavailable")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("FinTrack can't share its data with this widget.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
            HStack(spacing: 8) {
                quickAction("Expense", icon: "minus", kind: "expense")
                quickAction("Income", icon: "plus", kind: "income")
            }
            .padding(.top, 5)
        }
        .padding(4)
        .containerBackground(Color(red: 0.035, green: 0.045, blue: 0.047), for: .widget)
    }

    private func quickAction(_ title: String, icon: String, kind: String) -> some View {
        Link(destination: URL(string: "fintrack://quick-add?kind=\(kind)")!) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(.white.opacity(0.12), in: Capsule())
        }
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
