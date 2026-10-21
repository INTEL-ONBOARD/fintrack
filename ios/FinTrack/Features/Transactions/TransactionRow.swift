import SwiftUI

struct TransactionRow: View {
    let transaction: FinanceTransaction
    let categoryName: String

    private var isPositive: Bool {
        transaction.kind.isInflow || transaction.kind == .refund
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(isPositive ? FinTrackStyle.green : FinTrackStyle.purple)
                .frame(width: 38, height: 38)
                .background((isPositive ? FinTrackStyle.green : FinTrackStyle.purple).opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchant.isEmpty ? transaction.kind.title : transaction.merchant)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FinTrackStyle.ink)
                    .lineLimit(1)
                Text("\(categoryName) · \(transaction.occurredAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(isPositive ? "+" : "−") \(Money.formatted(transaction.amountMinor))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isPositive ? FinTrackStyle.green : FinTrackStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch transaction.kind {
        case .income, .interest: "arrow.down.left"
        case .transfer: "arrow.left.arrow.right"
        case .refund: "arrow.uturn.backward"
        case .cashWithdrawal: "banknote"
        default: "arrow.up.right"
        }
    }
}
