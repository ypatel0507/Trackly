import SwiftUI
import SwiftData
import UserNotifications
import UIKit

// MARK: - ACCOUNT TYPE

enum MoneyAccountType: String, CaseIterable, Identifiable, Codable {
    case chequing = "Chequing"
    case savings = "Savings"
    case cash = "Cash"
    case creditCard = "Credit Card"
    case investment = "Investment"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .chequing: return "building.columns.fill"
        case .savings: return "banknote.fill"
        case .cash: return "dollarsign.circle.fill"
        case .creditCard: return "creditcard.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .other: return "wallet.pass.fill"
        }
    }
}

// MARK: - ACCOUNT MOVEMENT TYPE

enum AccountMovementType: String, CaseIterable, Identifiable, Codable {
    case expense = "Expense"
    case income = "Income"
    case transferIn = "Transfer In"
    case transferOut = "Transfer Out"
    case adjustment = "Adjustment"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .expense: return "arrow.up.circle.fill"
        case .income: return "arrow.down.circle.fill"
        case .transferIn: return "arrow.down.left.circle.fill"
        case .transferOut: return "arrow.up.right.circle.fill"
        case .adjustment: return "slider.horizontal.3"
        }
    }
}


// MARK: - MONEY INPUT PARSING

enum MoneyInput {
    /// Parses user-typed money text. Accepts "$", spaces, thousands
    /// separators and the current locale's decimal separator
    /// (e.g. "12,50" in fr_CA). Returns nil for empty or invalid text.
    /// Result is rounded to cents so comparisons don't drift.
    static func parse(_ text: String) -> Double? {
        var clean = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")

        guard !clean.isEmpty else { return nil }

        let decimalSeparator = Locale.current.decimalSeparator ?? "."

        if decimalSeparator == "," {
            clean = clean
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        } else {
            clean = clean.replacingOccurrences(of: ",", with: "")
        }

        guard let value = Double(clean), value.isFinite else {
            return nil
        }

        return (value * 100).rounded() / 100
    }

    /// True when the field is empty or holds a valid amount.
    static func isEmptyOrValid(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || parse(text) != nil
    }

    /// Tolerance for comparing rounded currency values.
    static let epsilon = 0.005
}


// MARK: - MONEY LEDGER

enum MoneyLedger {
    /// Deletes a transaction and any account movements created with it,
    /// so the linked account balance is restored.
    @MainActor
    static func deleteTransaction(
        _ transaction: MoneyTransaction,
        context: ModelContext
    ) {
        let transactionID: UUID? = transaction.id

        let descriptor = FetchDescriptor<AccountMovement>(
            predicate: #Predicate { movement in
                movement.linkedTransactionID == transactionID
            }
        )

        let linked = (try? context.fetch(descriptor)) ?? []
        var touchedCards: [MoneyAccount] = []

        for movement in linked {
            if let account = movement.account {
                account.movements.removeAll { $0.id == movement.id }
                if account.type == .creditCard {
                    touchedCards.append(account)
                }
            }
            context.delete(movement)
        }

        context.delete(transaction)
        try? context.save()

        touchedCards.forEach(refreshCardReminders)
    }

    /// Adds an income movement to the chosen account so paychecks and
    /// other income raise the account balance.
    @MainActor
    static func depositIncome(
        amount: Double,
        date: Date,
        note: String,
        into account: MoneyAccount?,
        linkedTransactionID: UUID? = nil,
        linkedPaycheckID: UUID? = nil,
        context: ModelContext
    ) {
        guard let account, amount > 0 else { return }

        let movement = AccountMovement(
            amount: amount,
            date: date,
            type: .income,
            note: note,
            linkedTransactionID: linkedTransactionID,
            linkedPaycheckID: linkedPaycheckID,
            account: account
        )

        account.movements.append(movement)
        context.insert(movement)
        refreshCardReminders(account)
    }

    /// Best default account for deposits: first non-credit-card account.
    static func defaultDepositAccountID(
        in accounts: [MoneyAccount]
    ) -> UUID? {
        (accounts.first { $0.type != .creditCard } ?? accounts.first)?.id
    }

    /// Re-schedules a card's payment reminders so their text reflects
    /// the latest amount owed. No-op if the card has no due date.
    @MainActor
    static func refreshCardReminders(_ card: MoneyAccount) {
        guard
            card.type == .creditCard,
            card.paymentDueDate != nil
        else {
            return
        }

        let snapshot = card.notificationSnapshot

        Task {
            await CreditCardNotificationScheduler.reschedule(for: snapshot)
        }
    }
}


// MARK: - CREDIT CARD NOTIFICATIONS

struct CreditCardNotificationSnapshot: Sendable {
    let id: UUID
    let name: String
    let paymentDueDate: Date?
    let minimumPaymentDue: Double?
    let statementBalance: Double?
    let amountOwed: Double
}

enum CreditCardNotificationScheduler {

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current()
                .getNotificationSettings { settings in
                    continuation.resume(
                        returning: settings.authorizationStatus
                    )
                }
        }
    }

    static func ensurePermission() async -> Bool {
        let status = await authorizationStatus()

        switch status {
        case .authorized, .provisional, .ephemeral:
            return true

        case .notDetermined:
            do {
                return try await UNUserNotificationCenter.current()
                    .requestAuthorization(
                        options: [.alert, .sound, .badge]
                    )
            } catch {
                return false
            }

        case .denied:
            return false

        @unknown default:
            return false
        }
    }

    @discardableResult
    static func reschedule(
        for card: CreditCardNotificationSnapshot
    ) async -> Bool {
        removeNotifications(for: card.id)

        guard let dueDate = card.paymentDueDate else {
            return true
        }

        let granted = await ensurePermission()
        guard granted else {
            return false
        }

        let calendar = Calendar.current

        for daysBefore in [3, 1, 0] {
            guard let reminderDate = calendar.date(
                byAdding: .day,
                value: -daysBefore,
                to: dueDate
            ) else {
                continue
            }

            var components = calendar.dateComponents(
                [.year, .month, .day],
                from: reminderDate
            )
            components.hour = 9
            components.minute = 0
            components.second = 0

            guard
                let scheduledDate = calendar.date(from: components),
                scheduledDate > Date()
            else {
                continue
            }

            let content = UNMutableNotificationContent()

            switch daysBefore {
            case 0:
                content.title = "Payment Due Today"
            case 1:
                content.title = "Payment Due Tomorrow"
            default:
                content.title = "Payment Due in 3 Days"
            }

            content.body = notificationBody(
                for: card,
                daysBefore: daysBefore
            )
            content.sound = .default
            content.threadIdentifier = "trackly.credit-card-payments"

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )

            let request = UNNotificationRequest(
                identifier: notificationID(
                    cardID: card.id,
                    daysBefore: daysBefore
                ),
                content: content,
                trigger: trigger
            )

            do {
                try await UNUserNotificationCenter.current()
                    .add(request)
            } catch {
                // A failed reminder should never stop the rest of Trackly.
            }
        }

        return true
    }

    static func removeNotifications(for cardID: UUID) {
        let ids = [3, 1, 0].map {
            notificationID(
                cardID: cardID,
                daysBefore: $0
            )
        }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: ids
        )
        center.removeDeliveredNotifications(
            withIdentifiers: ids
        )
    }

    private static func notificationID(
        cardID: UUID,
        daysBefore: Int
    ) -> String {
        "trackly.credit-card.\(cardID.uuidString).\(daysBefore)"
    }

    private static func notificationBody(
        for card: CreditCardNotificationSnapshot,
        daysBefore: Int
    ) -> String {
        let amount = preferredPaymentAmount(for: card)

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CAD"

        let formattedAmount = formatter.string(
            from: NSNumber(value: amount)
        ) ?? "$0.00"

        let amountText: String

        if let minimum = card.minimumPaymentDue, minimum > 0 {
            amountText = "Minimum payment: \(formattedAmount)"
        } else if let statement = card.statementBalance, statement > 0 {
            amountText = "Statement balance: \(formattedAmount)"
        } else {
            amountText = "Amount owed: \(formattedAmount)"
        }

        if daysBefore == 0 {
            return "\(card.name) payment is due today. \(amountText)"
        }

        if daysBefore == 1 {
            return "\(card.name) payment is due tomorrow. \(amountText)"
        }

        return "\(card.name) payment is due in 3 days. \(amountText)"
    }

    private static func preferredPaymentAmount(
        for card: CreditCardNotificationSnapshot
    ) -> Double {
        if let minimum = card.minimumPaymentDue, minimum > 0 {
            return minimum
        }

        if let statement = card.statementBalance, statement > 0 {
            return statement
        }

        return card.amountOwed
    }
}


// MARK: - MONEY ACCOUNT MODEL

@Model
final class MoneyAccount: Identifiable {
    var id: UUID
    var name: String
    var typeRaw: String
    var startingBalance: Double
    var creditLimit: Double?
    var paymentDueDate: Date?
    var minimumPaymentDue: Double?
    var statementBalance: Double?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \AccountMovement.account)
    var movements: [AccountMovement]

    init(
        id: UUID = UUID(),
        name: String,
        type: MoneyAccountType,
        startingBalance: Double = 0,
        creditLimit: Double? = nil,
        paymentDueDate: Date? = nil,
        minimumPaymentDue: Double? = nil,
        statementBalance: Double? = nil,
        createdAt: Date = Date(),
        movements: [AccountMovement] = []
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.startingBalance = startingBalance
        self.creditLimit = creditLimit
        self.paymentDueDate = paymentDueDate
        self.minimumPaymentDue = minimumPaymentDue
        self.statementBalance = statementBalance
        self.createdAt = createdAt
        self.movements = movements
    }

    var type: MoneyAccountType {
        get { MoneyAccountType(rawValue: typeRaw) ?? .chequing }
        set { typeRaw = newValue.rawValue }
    }

    var currentBalance: Double {
        movements.reduce(startingBalance) { partial, movement in
            partial + movement.signedAmount
        }
    }

    var displayedBalance: Double {
        type == .creditCard ? abs(min(currentBalance, 0)) : currentBalance
    }

    var amountOwed: Double {
        guard type == .creditCard else { return 0 }
        return max(-currentBalance, 0)
    }

    var availableCredit: Double {
        guard
            type == .creditCard,
            let creditLimit,
            creditLimit > 0
        else {
            return 0
        }

        return max(creditLimit - amountOwed, 0)
    }

    var creditUtilization: Double {
        guard
            type == .creditCard,
            let creditLimit,
            creditLimit > 0
        else {
            return 0
        }

        return min(max(amountOwed / creditLimit, 0), 1)
    }

    var notificationSnapshot: CreditCardNotificationSnapshot {
        CreditCardNotificationSnapshot(
            id: id,
            name: name,
            paymentDueDate: paymentDueDate,
            minimumPaymentDue: minimumPaymentDue,
            statementBalance: statementBalance,
            amountOwed: amountOwed
        )
    }
}

// MARK: - ACCOUNT MOVEMENT MODEL

@Model
final class AccountMovement: Identifiable {
    var id: UUID
    var amount: Double
    var date: Date
    var typeRaw: String
    var note: String
    var linkedTransactionID: UUID?
    var linkedPaycheckID: UUID?
    var account: MoneyAccount?

    init(
        id: UUID = UUID(),
        amount: Double,
        date: Date = Date(),
        type: AccountMovementType,
        note: String = "",
        linkedTransactionID: UUID? = nil,
        linkedPaycheckID: UUID? = nil,
        account: MoneyAccount? = nil
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.typeRaw = type.rawValue
        self.note = note
        self.linkedTransactionID = linkedTransactionID
        self.linkedPaycheckID = linkedPaycheckID
        self.account = account
    }

    var type: AccountMovementType {
        get { AccountMovementType(rawValue: typeRaw) ?? .adjustment }
        set { typeRaw = newValue.rawValue }
    }

    var signedAmount: Double {
        switch type {
        case .expense, .transferOut:
            return -abs(amount)
        case .income, .transferIn:
            return abs(amount)
        case .adjustment:
            return amount
        }
    }
}


// MARK: - MONTHLY BUDGET MODEL

@Model
final class MonthlyBudget: Identifiable {
    var id: UUID
    var categoryRaw: String
    var limit: Double
    var monthStart: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        category: ExpenseCategory,
        limit: Double,
        monthStart: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.categoryRaw = category.rawValue
        self.limit = limit
        self.monthStart = Calendar.current.startOfMonth(for: monthStart)
        self.createdAt = createdAt
    }

    var category: ExpenseCategory {
        get {
            ExpenseCategory(rawValue: categoryRaw) ?? .other
        }
        set {
            categoryRaw = newValue.rawValue
        }
    }
}


// MARK: - MONTHLY BUDGET HELPERS

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents(
            [.year, .month],
            from: date
        )

        return self.date(from: components) ?? startOfDay(for: date)
    }
}


// MARK: - ACCOUNTS SECTION

struct MoneyAccountsSection: View {
    @Query(sort: \MoneyAccount.createdAt)
    private var accounts: [MoneyAccount]

    @State private var showAddAccount = false
    @State private var showTransfer = false

    private var totalBalance: Double {
        accounts.reduce(0) { $0 + $1.currentBalance }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if accounts.isEmpty {
                emptyState
            } else {
                totalBalanceCard
                accountList
            }

            MonthlyBudgetSection()
                .padding(.top, 8)
        }
        .sheet(isPresented: $showAddAccount) {
            AddMoneyAccountView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTransfer) {
            MoneyTransferView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Accounts")
                    .font(.system(size: 21, weight: .bold, design: .rounded))

                Text(
                    accounts.isEmpty
                    ? "Add where you keep your money"
                    : "\(accounts.count) account\(accounts.count == 1 ? "" : "s")"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if accounts.count >= 2 {
                Button {
                    showTransfer = true
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .fontWeight(.semibold)
                        .foregroundStyle(.indigo)
                        .frame(width: 36, height: 36)
                        .background(Color.indigo.opacity(0.09), in: Circle())
                }
            }

            Button {
                showAddAccount = true
            } label: {
                Image(systemName: "plus")
                    .fontWeight(.bold)
                    .foregroundStyle(.indigo)
                    .frame(width: 36, height: 36)
                    .background(Color.indigo.opacity(0.09), in: Circle())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.columns.fill")
                .font(.title2)
                .foregroundStyle(.indigo)

            Text("Add your first account")
                .font(.headline)

            Text("Chequing, savings, cash, credit cards and more.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showAddAccount = true
            } label: {
                Label("Add Account", systemImage: "plus")
                    .fontWeight(.semibold)
                    .foregroundStyle(.indigo)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(cardBackground)
    }

    private var totalBalanceCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("TOTAL BALANCE")
                    .font(.caption2)
                    .fontWeight(.black)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                Text(totalBalance, format: .currency(code: "CAD"))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(totalBalance < 0 ? Color.red : Color.primary)
            }

            Spacer()

            Image(systemName: "wallet.pass.fill")
                .font(.title2)
                .foregroundStyle(.indigo)
        }
        .padding(17)
        .background(cardBackground)
    }

    private var accountList: some View {
        VStack(spacing: 10) {
            ForEach(accounts, id: \.id) { account in
                NavigationLink {
                    MoneyAccountDetailView(account: account)
                } label: {
                    MoneyAccountCard(account: account)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }
}


// MARK: - MONTHLY BUDGET SECTION

struct MonthlyBudgetSection: View {
    @Query(sort: \MonthlyBudget.createdAt)
    private var budgets: [MonthlyBudget]

    @Query(sort: \MoneyTransaction.date, order: .reverse)
    private var transactions: [MoneyTransaction]

    @State private var showBudgetEditor = false

    private var calendar: Calendar {
        .current
    }

    private var currentMonthStart: Date {
        calendar.startOfMonth(for: Date())
    }

    private var currentMonthBudgets: [MonthlyBudget] {
        budgets.filter {
            calendar.isDate(
                $0.monthStart,
                equalTo: currentMonthStart,
                toGranularity: .month
            )
        }
    }

    private var monthExpenses: [MoneyTransaction] {
        transactions.filter { transaction in
            guard transaction.type == .expense else {
                return false
            }

            return calendar.isDate(
                transaction.date,
                equalTo: currentMonthStart,
                toGranularity: .month
            )
        }
    }

    private var totalBudget: Double {
        currentMonthBudgets.reduce(0) {
            $0 + max($1.limit, 0)
        }
    }

    private var totalSpent: Double {
        monthExpenses.reduce(0) {
            $0 + abs($1.amount)
        }
    }

    private var remaining: Double {
        totalBudget - totalSpent
    }

    private var progress: Double {
        guard totalBudget > 0 else {
            return 0
        }

        return totalSpent / totalBudget
    }

    private var monthTitle: String {
        currentMonthStart.formatted(
            .dateTime.month(.wide).year()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if currentMonthBudgets.isEmpty {
                emptyState
            } else {
                summaryCard

                VStack(spacing: 10) {
                    ForEach(
                        currentMonthBudgets.sorted {
                            $0.category.rawValue < $1.category.rawValue
                        },
                        id: \.id
                    ) { budget in
                        MonthlyBudgetRow(
                            budget: budget,
                            spent: spent(
                                for: budget.category
                            )
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showBudgetEditor) {
            MonthlyBudgetEditorView(
                monthStart: currentMonthStart
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Monthly Budget")
                    .font(
                        .system(
                            size: 21,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                Text(monthTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showBudgetEditor = true
            } label: {
                Image(
                    systemName:
                        currentMonthBudgets.isEmpty
                        ? "plus"
                        : "slider.horizontal.3"
                )
                .fontWeight(.bold)
                .foregroundStyle(.indigo)
                .frame(width: 36, height: 36)
                .background(
                    Color.indigo.opacity(0.09),
                    in: Circle()
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie.fill")
                .font(.title2)
                .foregroundStyle(.indigo)

            Text("Plan this month's spending")
                .font(.headline)

            Text(
                "Set limits for Food, Shopping, Transport and your other expense categories."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Button {
                showBudgetEditor = true
            } label: {
                Label(
                    "Set Monthly Budget",
                    systemImage: "plus"
                )
                .fontWeight(.semibold)
                .foregroundStyle(.indigo)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(cardBackground)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAL MONTHLY BUDGET")
                        .font(.caption2)
                        .fontWeight(.black)
                        .tracking(1.4)
                        .foregroundStyle(.secondary)

                    Text(
                        totalSpent,
                        format: .currency(code: "CAD")
                    )
                    .font(
                        .system(
                            size: 27,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                    Text(
                        "of \(totalBudget.formatted(.currency(code: "CAD"))) spent"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(
                        remaining >= 0
                        ? "REMAINING"
                        : "OVER BUDGET"
                    )
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                    Text(
                        abs(remaining),
                        format: .currency(code: "CAD")
                    )
                    .font(.headline)
                    .foregroundStyle(
                        remaining < 0
                        ? Color.red
                        : Color.primary
                    )
                }
            }

            ProgressView(
                value: min(max(progress, 0), 1)
            )
            .tint(
                progress >= 1
                ? .red
                : progress >= 0.8
                ? .orange
                : .indigo
            )

            HStack {
                Text(
                    "\(Int((progress * 100).rounded()))% used"
                )
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(
                    progress >= 1
                    ? Color.red
                    : progress >= 0.8
                    ? Color.orange
                    : Color.secondary
                )

                Spacer()

                if progress >= 1 {
                    Label(
                        "Over budget",
                        systemImage:
                            "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                } else if progress >= 0.8 {
                    Label(
                        "Almost there",
                        systemImage:
                            "exclamationmark.circle.fill"
                    )
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                }
            }
        }
        .padding(17)
        .background(cardBackground)
    }

    private func spent(
        for category: ExpenseCategory
    ) -> Double {
        monthExpenses
            .filter {
                $0.category == category
            }
            .reduce(0) {
                $0 + abs($1.amount)
            }
    }

    private var cardBackground: some View {
        RoundedRectangle(
            cornerRadius: 20,
            style: .continuous
        )
        .fill(
            Color(
                uiColor:
                    .secondarySystemGroupedBackground
            )
        )
    }
}


// MARK: - MONTHLY BUDGET ROW

struct MonthlyBudgetRow: View {
    let budget: MonthlyBudget
    let spent: Double

    private var remaining: Double {
        budget.limit - spent
    }

    private var progress: Double {
        guard budget.limit > 0 else {
            return 0
        }

        return spent / budget.limit
    }

    private var statusColor: Color {
        if progress >= 1 {
            return .red
        }

        if progress >= 0.8 {
            return .orange
        }

        return .indigo
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: budget.category.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 40, height: 40)
                    .background(
                        Color.indigo.opacity(0.09),
                        in: RoundedRectangle(
                            cornerRadius: 13
                        )
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(budget.category.rawValue)
                        .font(.headline)

                    Text(
                        "\(spent.formatted(.currency(code: "CAD"))) of \(budget.limit.formatted(.currency(code: "CAD")))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(
                        "\(Int((progress * 100).rounded()))%"
                    )
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(statusColor)

                    Text(
                        remaining >= 0
                        ? "\(remaining.formatted(.currency(code: "CAD"))) left"
                        : "\(abs(remaining).formatted(.currency(code: "CAD"))) over"
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        remaining < 0
                        ? Color.red
                        : Color.secondary
                    )
                }
            }

            ProgressView(
                value: min(max(progress, 0), 1)
            )
            .tint(statusColor)
        }
        .padding(15)
        .background(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .fill(
                Color(
                    uiColor:
                        .secondarySystemGroupedBackground
                )
            )
        )
    }
}


// MARK: - MONTHLY BUDGET EDITOR

struct MonthlyBudgetEditorView: View {
    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.dismiss)
    private var dismiss

    @Query(sort: \MonthlyBudget.createdAt)
    private var allBudgets: [MonthlyBudget]

    let monthStart: Date

    @State private var amounts:
        [ExpenseCategory: String] = [:]

    private var calendar: Calendar {
        .current
    }

    private var existingBudgets: [MonthlyBudget] {
        allBudgets.filter {
            calendar.isDate(
                $0.monthStart,
                equalTo: monthStart,
                toGranularity: .month
            )
        }
    }

    private var monthTitle: String {
        monthStart.formatted(
            .dateTime.month(.wide).year()
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 20
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 5
                    ) {
                        Text("MONTHLY PLAN")
                            .font(.caption2)
                            .fontWeight(.black)
                            .tracking(2)
                            .foregroundStyle(.indigo)

                        Text(monthTitle)
                            .font(
                                .system(
                                    size: 30,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )

                        Text(
                            "Enter a limit only for the categories you want to budget."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 10) {
                        ForEach(
                            ExpenseCategory.allCases
                        ) { category in
                            budgetField(for: category)
                        }
                    }

                    infoCard

                    Button {
                        saveBudgets()
                    } label: {
                        Text("Save Monthly Budget")
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                Color.indigo,
                                in: RoundedRectangle(
                                    cornerRadius: 17
                                )
                            )
                    }
                }
                .padding(20)
            }
            .background(
                Color(
                    uiColor:
                        .systemGroupedBackground
                )
            )
            .navigationTitle("Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .topBarLeading
                ) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadExistingBudgets()
            }
        }
    }

    private func budgetField(
        for category: ExpenseCategory
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.indigo)
                .frame(width: 40, height: 40)
                .background(
                    Color.indigo.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 13
                    )
                )

            Text(category.rawValue)
                .fontWeight(.semibold)

            Spacer()

            HStack(spacing: 4) {
                Text("$")
                    .foregroundStyle(.secondary)

                TextField(
                    "0",
                    text: Binding(
                        get: {
                            amounts[category] ?? ""
                        },
                        set: {
                            amounts[category] = $0
                        }
                    )
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .fill(
                Color(
                    uiColor:
                        .secondarySystemGroupedBackground
                )
            )
        )
    }

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.indigo)

            Text(
                "Your spending updates automatically from expenses already recorded in Trackly. You do not need to update these progress bars manually."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    Color.indigo.opacity(0.07)
                )
        )
    }

    private func loadExistingBudgets() {
        for category in ExpenseCategory.allCases {
            guard
                let budget =
                    existingBudgets.first(
                        where: {
                            $0.category == category
                        }
                    )
            else {
                continue
            }

            amounts[category] =
                String(
                    format: "%.2f",
                    budget.limit
                )
        }
    }

    private func saveBudgets() {
        for category in ExpenseCategory.allCases {
            let raw = amounts[category] ?? ""

            let existing =
                existingBudgets.first {
                    $0.category == category
                }

            // Typo'd text (e.g. "abc") should never wipe out a budget.
            guard MoneyInput.isEmptyOrValid(raw) else {
                continue
            }

            let value = MoneyInput.parse(raw) ?? 0

            if value > 0 {
                if let existing {
                    existing.limit = value
                } else {
                    let budget = MonthlyBudget(
                        category: category,
                        limit: value,
                        monthStart: monthStart
                    )

                    modelContext.insert(budget)
                }
            } else if let existing {
                modelContext.delete(existing)
            }
        }

        try? modelContext.save()
        dismiss()
    }
}


// MARK: - ACCOUNT CARD

struct MoneyAccountCard: View {
    let account: MoneyAccount

    var body: some View {
        HStack(spacing: 14) {
            accountIcon
            accountInfo
            Spacer()
            balanceInfo

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var accountIcon: some View {
        Image(systemName: account.type.icon)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(
                LinearGradient(
                    colors: [.indigo, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }

    private var accountInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(account.name)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text(account.type.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var balanceInfo: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if account.type == .creditCard {
                Text(account.amountOwed, format: .currency(code: "CAD"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if account.creditLimit != nil {
                    Text(
                        "\(account.availableCredit.formatted(.currency(code: "CAD"))) available"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Owed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(account.currentBalance, format: .currency(code: "CAD"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        account.currentBalance < 0 ? Color.red : Color.primary
                    )

                Text("Balance")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - ADD ACCOUNT

struct AddMoneyAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: MoneyAccountType = .chequing
    @State private var startingBalance = ""
    @State private var creditLimit = ""

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    private var balanceValue: Double {
        MoneyInput.parse(startingBalance) ?? 0
    }

    private var cleanName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var creditLimitValue: Double {
        MoneyInput.parse(creditLimit) ?? 0
    }

    private var canSave: Bool {
        guard
            !cleanName.isEmpty,
            MoneyInput.isEmptyOrValid(startingBalance)
        else {
            return false
        }

        if type == .creditCard {
            return creditLimitValue > 0 &&
                balanceValue >= 0 &&
                balanceValue <= creditLimitValue + MoneyInput.epsilon
        }

        return true
    }

    private var balanceTitle: String {
        type == .creditCard ? "AMOUNT OWED" : "CURRENT BALANCE"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    nameField
                    accountTypePicker
                    if type == .creditCard {
                        creditLimitField
                    }

                    balanceField

                    if type == .creditCard {
                        creditCardPreview
                        creditCardHint
                    }

                    saveButton
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("New Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("NEW ACCOUNT")
                .font(.caption2)
                .fontWeight(.black)
                .tracking(2)
                .foregroundStyle(.indigo)

            Text("Add an account")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("Tell Trackly where your money is kept.")
                .foregroundStyle(.secondary)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACCOUNT NAME")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            TextField("e.g. Main Chequing", text: $name)
                .padding()
                .background(fieldBackground)
        }
    }

    private var accountTypePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACCOUNT TYPE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(MoneyAccountType.allCases) { option in
                    typeButton(option)
                }
            }
        }
    }

    private func typeButton(_ option: MoneyAccountType) -> some View {
        let selected = type == option

        return Button {
            type = option
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.icon)

                Text(option.rawValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer()
            }
            .foregroundStyle(selected ? Color.white : Color.indigo)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Color.indigo : Color.indigo.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 15)
            )
        }
        .buttonStyle(.plain)
    }

    private var creditLimitField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CREDIT LIMIT")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            HStack {
                Text("$")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                TextField("5000.00", text: $creditLimit)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
            }
            .padding()
            .background(fieldBackground)
        }
    }

    private var balanceField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(balanceTitle)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            HStack {
                Text("$")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                TextField("0.00", text: $startingBalance)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
            }
            .padding()
            .background(fieldBackground)
        }
    }

    private var creditCardPreview: some View {
        let available = max(creditLimitValue - balanceValue, 0)
        let utilization =
            creditLimitValue > 0
            ? min(max(balanceValue / creditLimitValue, 0), 1)
            : 0

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AVAILABLE CREDIT")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text(available, format: .currency(code: "CAD"))
                    .font(.headline)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("UTILIZATION")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)

                Text("\(Int(utilization * 100))%")
                    .font(.headline)
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.indigo.opacity(0.07))
        )
    }

    private var creditCardHint: some View {
        Text(
            "Enter your total card limit and the amount you already owe. Trackly stores card debt internally as a negative balance so your total balance stays accurate."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var saveButton: some View {
        Button {
            createAccount()
        } label: {
            Text("Add Account")
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Color.indigo,
                    in: RoundedRectangle(cornerRadius: 17)
                )
        }
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.5)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func createAccount() {
        guard canSave else { return }

        let storedBalance: Double
        if type == .creditCard {
            storedBalance = -abs(balanceValue)
        } else {
            storedBalance = balanceValue
        }

        let account = MoneyAccount(
            name: cleanName,
            type: type,
            startingBalance: storedBalance,
            creditLimit: type == .creditCard ? creditLimitValue : nil
        )

        modelContext.insert(account)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - ACCOUNT DETAIL

struct MoneyAccountDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var account: MoneyAccount

    @State private var showAdjustment = false
    @State private var showDeleteAlert = false
    @State private var showCreditPurchase = false
    @State private var showCreditPayment = false
    @State private var showCardBilling = false

    private var orderedMovements: [AccountMovement] {
        account.movements.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                balanceCard

                if account.type == .creditCard {
                    creditCardBillingCard
                    creditCardActions
                }

                adjustButton
                activitySection
                deleteButton
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdjustment) {
            AccountBalanceAdjustmentView(account: account)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showCreditPurchase) {
            CreditCardPurchaseView(account: account)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCreditPayment) {
            CreditCardPaymentView(card: account)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCardBilling) {
            CreditCardBillingView(card: account)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "Delete \(account.name)?",
            isPresented: $showDeleteAlert
        ) {
            Button("Cancel", role: .cancel) {}

            Button("Delete", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("This will also remove this account's activity history.")
        }
    }

    private func deleteAccount() {
        // Cancel any pending payment reminders for this card.
        CreditCardNotificationScheduler.removeNotifications(for: account.id)

        let accountToDelete = account
        let context = modelContext

        // Leave the screen first; deleting a SwiftData model while its
        // detail view is still rendering can crash on property access.
        dismiss()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            context.delete(accountToDelete)
            try? context.save()
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: account.type.icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        Color.indigo,
                        in: RoundedRectangle(cornerRadius: 15)
                    )

                VStack(alignment: .leading) {
                    Text(account.name)
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text(account.type.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(account.type == .creditCard ? "AMOUNT OWED" : "CURRENT BALANCE")
                .font(.caption2)
                .fontWeight(.black)
                .tracking(1.5)
                .foregroundStyle(.secondary)

            if account.type == .creditCard {
                Text(account.amountOwed, format: .currency(code: "CAD"))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if let creditLimit = account.creditLimit {
                    Divider()
                        .padding(.vertical, 4)

                    HStack {
                        creditMetric(
                            title: "LIMIT",
                            value: creditLimit.formatted(
                                .currency(code: "CAD")
                            )
                        )

                        Spacer()

                        creditMetric(
                            title: "AVAILABLE",
                            value: account.availableCredit.formatted(
                                .currency(code: "CAD")
                            )
                        )
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("UTILIZATION")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("\(Int(account.creditUtilization * 100))%")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }

                        ProgressView(value: account.creditUtilization)
                            .tint(.indigo)
                    }
                }
            } else {
                Text(account.currentBalance, format: .currency(code: "CAD"))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        account.currentBalance < 0 ? Color.red : Color.primary
                    )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func creditMetric(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
        }
    }



    private var creditCardBillingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PAYMENT DUE")
                        .font(.caption2)
                        .fontWeight(.black)
                        .tracking(1.4)
                        .foregroundStyle(.secondary)

                    if let dueDate = account.paymentDueDate {
                        Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.headline)

                        Text(dueStatusText(for: dueDate))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(dueStatusColor(for: dueDate))
                    } else {
                        Text("Not set")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    showCardBilling = true
                } label: {
                    Image(systemName: "pencil")
                        .fontWeight(.bold)
                        .frame(width: 38, height: 38)
                        .background(
                            Color.indigo.opacity(0.10),
                            in: Circle()
                        )
                }
            }

            if account.minimumPaymentDue != nil || account.statementBalance != nil {
                Divider()

                HStack {
                    if let minimum = account.minimumPaymentDue {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("MINIMUM DUE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)

                            Text(
                                minimum,
                                format: .currency(code: "CAD")
                            )
                            .font(.headline)
                        }
                    }

                    Spacer()

                    if let statement = account.statementBalance {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("STATEMENT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)

                            Text(
                                statement,
                                format: .currency(code: "CAD")
                            )
                            .font(.headline)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func dueStatusText(for dueDate: Date) -> String {
        let calendar = Calendar.current
        let startToday = calendar.startOfDay(for: Date())
        let startDue = calendar.startOfDay(for: dueDate)
        let days = calendar.dateComponents(
            [.day],
            from: startToday,
            to: startDue
        ).day ?? 0

        if days < 0 {
            let overdue = abs(days)
            return overdue == 1
                ? "1 day overdue"
                : "\(overdue) days overdue"
        }

        if days == 0 {
            return "Due today"
        }

        if days == 1 {
            return "Due tomorrow"
        }

        return "Due in \(days) days"
    }

    private func dueStatusColor(for dueDate: Date) -> Color {
        let calendar = Calendar.current
        let startToday = calendar.startOfDay(for: Date())
        let startDue = calendar.startOfDay(for: dueDate)
        let days = calendar.dateComponents(
            [.day],
            from: startToday,
            to: startDue
        ).day ?? 0

        if days < 0 {
            return .red
        }

        if days <= 3 {
            return .orange
        }

        return .secondary
    }

    private var creditCardActions: some View {
        HStack(spacing: 12) {
            Button {
                showCreditPurchase = true
            } label: {
                Label("Add Purchase", systemImage: "cart.fill")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Color.indigo,
                        in: RoundedRectangle(cornerRadius: 17)
                    )
            }

            Button {
                showCreditPayment = true
            } label: {
                Label("Make Payment", systemImage: "arrow.down.circle.fill")
                    .fontWeight(.semibold)
                    .foregroundStyle(.indigo)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Color.indigo.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 17)
                    )
            }
        }
    }

    private var adjustButton: some View {
        Button {
            showAdjustment = true
        } label: {
            Label("Adjust Balance", systemImage: "slider.horizontal.3")
                .fontWeight(.semibold)
                .foregroundStyle(.indigo)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Color.indigo.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 17)
                )
        }
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity")
                .font(.system(size: 21, weight: .bold, design: .rounded))

            if orderedMovements.isEmpty {
                emptyActivity
            } else {
                VStack(spacing: 10) {
                    ForEach(orderedMovements, id: \.id) { movement in
                        AccountMovementRow(movement: movement)
                    }
                }
            }
        }
    }

    private var emptyActivity: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.title2)
                .foregroundStyle(.indigo)

            Text("No account activity yet")
                .font(.headline)

            Text("Expenses, income, transfers and balance adjustments will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteAlert = true
        } label: {
            Label("Delete Account", systemImage: "trash")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Color.red.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 17)
                )
        }
    }
}

// MARK: - MOVEMENT ROW

struct AccountMovementRow: View {
    let movement: AccountMovement

    private var positive: Bool {
        movement.signedAmount >= 0
    }

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: movement.type.icon)
                .foregroundStyle(positive ? Color.green : Color.indigo)
                .frame(width: 42, height: 42)
                .background(
                    (positive ? Color.green : Color.indigo).opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 12)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    movement.note.isEmpty
                    ? movement.type.rawValue
                    : movement.note
                )
                .fontWeight(.semibold)

                Text(
                    movement.date.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(
                "\(positive ? "+" : "-")\(abs(movement.signedAmount).formatted(.currency(code: "CAD")))"
            )
            .fontWeight(.bold)
            .foregroundStyle(positive ? Color.green : Color.primary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

// MARK: - BALANCE ADJUSTMENT

struct AccountBalanceAdjustmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let account: MoneyAccount

    @State private var newBalance = ""

    private var enteredValue: Double? {
        MoneyInput.parse(newBalance)
    }

    private var desiredStoredBalance: Double? {
        guard let value = enteredValue else { return nil }
        if account.type == .creditCard {
            // User enters amount owed; card debt is stored as negative.
            // A negative entry means a credit balance on the card.
            return -value
        }
        return value
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Adjust Balance")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text(currentBalanceDescription)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("$")
                        .font(.title)

                    TextField("New balance", text: $newBalance)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 17)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )

                if account.type == .creditCard {
                    Text("Enter the amount currently owed as a positive number.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    saveAdjustment()
                } label: {
                    Text("Update Balance")
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            Color.indigo,
                            in: RoundedRectangle(cornerRadius: 17)
                        )
                }
                .disabled(desiredStoredBalance == nil)
                .opacity(desiredStoredBalance == nil ? 0.45 : 1)

                Spacer()
            }
            .padding(20)
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    private var currentBalanceDescription: String {
        if account.type == .creditCard {
            return "Currently owed: \(account.displayedBalance.formatted(.currency(code: "CAD")))"
        }
        return "Current balance: \(account.currentBalance.formatted(.currency(code: "CAD")))"
    }

    private func saveAdjustment() {
        guard let desired = desiredStoredBalance else { return }

        let difference = desired - account.currentBalance

        if abs(difference) < 0.001 {
            dismiss()
            return
        }

        let movement = AccountMovement(
            amount: difference,
            type: .adjustment,
            note: "Balance adjustment",
            account: account
        )

        account.movements.append(movement)
        modelContext.insert(movement)
        try? modelContext.save()
        MoneyLedger.refreshCardReminders(account)
        dismiss()
    }
}

// MARK: - TRANSFER MONEY

struct MoneyTransferView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \MoneyAccount.createdAt)
    private var accounts: [MoneyAccount]

    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var amount = ""
    @State private var note = ""

    private var amountValue: Double {
        MoneyInput.parse(amount) ?? 0
    }

    private var fromAccount: MoneyAccount? {
        accounts.first { $0.id == fromID }
    }

    private var toAccount: MoneyAccount? {
        accounts.first { $0.id == toID }
    }

    /// Moving money off a credit card (cash advance) can't exceed
    /// its available credit.
    private var exceedsCreditLimit: Bool {
        guard
            let fromAccount,
            fromAccount.type == .creditCard,
            let limit = fromAccount.creditLimit,
            limit > 0
        else {
            return false
        }

        return amountValue > fromAccount.availableCredit + MoneyInput.epsilon
    }

    private var canSave: Bool {
        amountValue > 0 &&
        fromAccount != nil &&
        toAccount != nil &&
        fromID != toID &&
        !exceedsCreditLimit
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    fromPicker
                    toPicker
                    amountField

                    if fromID != nil && fromID == toID {
                        Text("Choose two different accounts.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if exceedsCreditLimit, let fromAccount {
                        Text("Exceeds available credit (\(fromAccount.availableCredit.formatted(.currency(code: "CAD")))).")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    noteField
                    saveButton
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if fromID == nil {
                    fromID = accounts.first?.id
                }

                if toID == nil {
                    toID = accounts.dropFirst().first?.id
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TRANSFER")
                .font(.caption2)
                .fontWeight(.black)
                .tracking(2)
                .foregroundStyle(.indigo)

            Text("Move your money")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("Transfers won't count as spending or income.")
                .foregroundStyle(.secondary)
        }
    }

    private var fromPicker: some View {
        pickerSection(
            title: "FROM",
            selection: $fromID,
            placeholder: "Choose account"
        )
    }

    private var toPicker: some View {
        pickerSection(
            title: "TO",
            selection: $toID,
            placeholder: "Choose account"
        )
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AMOUNT")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            HStack {
                Text("$")
                    .font(.title)

                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
            }
            .padding()
            .background(fieldBackground)
        }
    }

    private var noteField: some View {
        TextField("Note (optional)", text: $note)
            .padding()
            .background(fieldBackground)
    }

    private var saveButton: some View {
        Button {
            saveTransfer()
        } label: {
            Text("Transfer Money")
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Color.indigo,
                    in: RoundedRectangle(cornerRadius: 17)
                )
        }
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.45)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 17)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func pickerSection(
        title: String,
        selection: Binding<UUID?>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            Picker(placeholder, selection: selection) {
                Text(placeholder)
                    .tag(Optional<UUID>.none)

                ForEach(accounts, id: \.id) { account in
                    Label(account.name, systemImage: account.type.icon)
                        .tag(Optional(account.id))
                }
            }
            .pickerStyle(.menu)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fieldBackground)
        }
    }

    private func saveTransfer() {
        guard canSave, let fromAccount, let toAccount else { return }

        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let outgoing = AccountMovement(
            amount: amountValue,
            type: .transferOut,
            note: cleanNote.isEmpty ? "Transfer to \(toAccount.name)" : cleanNote,
            account: fromAccount
        )

        let incoming = AccountMovement(
            amount: amountValue,
            type: .transferIn,
            note: cleanNote.isEmpty ? "Transfer from \(fromAccount.name)" : cleanNote,
            account: toAccount
        )

        fromAccount.movements.append(outgoing)
        toAccount.movements.append(incoming)

        modelContext.insert(outgoing)
        modelContext.insert(incoming)

        try? modelContext.save()
        MoneyLedger.refreshCardReminders(fromAccount)
        MoneyLedger.refreshCardReminders(toAccount)
        dismiss()
    }
}



// MARK: - CREDIT CARD BILLING

struct CreditCardBillingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let card: MoneyAccount

    @State private var dueDate = Date()
    @State private var hasDueDate = false
    @State private var minimumPayment = ""
    @State private var statementBalance = ""
    @State private var showNotificationDeniedAlert = false
    @State private var isSaving = false

    private var minimumValue: Double? {
        MoneyInput.parse(minimumPayment)
    }

    private var statementValue: Double? {
        MoneyInput.parse(statementBalance)
    }

    private var inputsValid: Bool {
        MoneyInput.isEmptyOrValid(minimumPayment) &&
        MoneyInput.isEmptyOrValid(statementBalance) &&
        (minimumValue ?? 0) >= 0 &&
        (statementValue ?? 0) >= 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    dueDateSection
                    minimumSection
                    statementSection
                    infoCard
                    saveButton
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Card Billing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadExistingValues()
            }
            .alert(
                "Notifications Are Off",
                isPresented: $showNotificationDeniedAlert
            ) {
                Button("Open Settings") {
                    openNotificationSettings()
                }

                Button("Not Now", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(
                    "Your billing details were saved, but Trackly cannot send payment reminders until notifications are enabled in iPhone Settings."
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BILLING DETAILS")
                .font(.caption2)
                .fontWeight(.black)
                .tracking(2)
                .foregroundStyle(.indigo)

            Text(card.name)
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("Track the next payment due date and statement amount.")
                .foregroundStyle(.secondary)
        }
    }

    private var dueDateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Track payment due date", isOn: $hasDueDate)
                .fontWeight(.semibold)

            if hasDueDate {
                DatePicker(
                    "Next due date",
                    selection: $dueDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()
                .background(fieldBackground)
            }
        }
    }

    private var minimumSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("MINIMUM PAYMENT DUE")

            HStack {
                Text("$")
                    .font(.title3)

                TextField("0.00", text: $minimumPayment)
                    .keyboardType(.decimalPad)
            }
            .padding()
            .background(fieldBackground)
        }
    }

    private var statementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("STATEMENT BALANCE")

            HStack {
                Text("$")
                    .font(.title3)

                TextField("0.00", text: $statementBalance)
                    .keyboardType(.decimalPad)
            }
            .padding()
            .background(fieldBackground)
        }
    }

    private var infoCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .foregroundStyle(.indigo)

            VStack(alignment: .leading, spacing: 5) {
                Text("Payment reminders")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(
                    "When a due date is saved, Trackly schedules reminders at 9:00 AM: 3 days before, 1 day before, and on the due date. Saving again replaces the old reminders, so duplicates are avoided."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.indigo.opacity(0.07))
        )
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                }

                Text(
                    isSaving
                    ? "Saving..."
                    : "Save Billing Details"
                )
                .fontWeight(.bold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
                .background(
                    Color.indigo,
                    in: RoundedRectangle(cornerRadius: 17)
                )
        }
        .disabled(isSaving || !inputsValid)
        .opacity(inputsValid ? 1 : 0.45)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 17)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func loadExistingValues() {
        if let existing = card.paymentDueDate {
            dueDate = existing
            hasDueDate = true
        } else {
            dueDate = Calendar.current.date(
                byAdding: .day,
                value: 21,
                to: Date()
            ) ?? Date()
            hasDueDate = false
        }

        if let minimum = card.minimumPaymentDue {
            minimumPayment = String(format: "%.2f", minimum)
        }

        if let statement = card.statementBalance {
            statementBalance = String(format: "%.2f", statement)
        }
    }

    private func save() {
        guard !isSaving, inputsValid else { return }

        let trackDueDate = hasDueDate

        card.paymentDueDate = trackDueDate
            ? Calendar.current.startOfDay(for: dueDate)
            : nil
        card.minimumPaymentDue = minimumValue
        card.statementBalance = statementValue

        try? modelContext.save()

        let snapshot = card.notificationSnapshot

        let cardID = card.id
        isSaving = true

        Task {
            let notificationsReady: Bool

            if trackDueDate {
                notificationsReady =
                    await CreditCardNotificationScheduler
                        .reschedule(for: snapshot)
            } else {
                CreditCardNotificationScheduler
                    .removeNotifications(for: cardID)
                notificationsReady = true
            }

            await MainActor.run {
                isSaving = false

                if trackDueDate && !notificationsReady {
                    showNotificationDeniedAlert = true
                } else {
                    dismiss()
                }
            }
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(
            string: UIApplication.openSettingsURLString
        ) else {
            return
        }

        UIApplication.shared.open(url)
        dismiss()
    }
}


// MARK: - CREDIT CARD PURCHASE

struct CreditCardPurchaseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let account: MoneyAccount

    @State private var amount = ""
    @State private var merchant = ""
    @State private var category: ExpenseCategory = .other
    @State private var note = ""
    @State private var date = Date()

    private var amountValue: Double { MoneyInput.parse(amount) ?? 0 }

    private var canSave: Bool {
        guard amountValue > 0 else { return false }
        if let limit = account.creditLimit, limit > 0 {
            return amountValue <= account.availableCredit + MoneyInput.epsilon
        }
        return true
    }

    private var availableAfterPurchase: Double {
        max(account.availableCredit - amountValue, 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("ADD PURCHASE")
                        .font(.caption2)
                        .fontWeight(.black)
                        .tracking(2)
                        .foregroundStyle(.indigo)

                    Text(account.name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text("Currently owed: \(account.amountOwed.formatted(.currency(code: "CAD")))")
                        .foregroundStyle(.secondary)

                    fieldLabel("PURCHASE AMOUNT")
                    HStack {
                        Text("$").font(.title2)
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                    }
                    .padding()
                    .background(fieldBackground)

                    fieldLabel("MERCHANT")
                    TextField("e.g. Amazon", text: $merchant)
                        .padding()
                        .background(fieldBackground)

                    fieldLabel("CATEGORY")
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { item in
                            Label(item.rawValue, systemImage: item.icon).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(fieldBackground)

                    fieldLabel("DATE")
                    DatePicker("Purchase Date", selection: $date, displayedComponents: [.date])
                        .labelsHidden()
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(fieldBackground)

                    fieldLabel("NOTE")
                    TextField("Optional note", text: $note)
                        .padding()
                        .background(fieldBackground)

                    if account.creditLimit != nil {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("AVAILABLE AFTER")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Text(availableAfterPurchase, format: .currency(code: "CAD"))
                                    .font(.headline)
                            }
                            Spacer()
                            if let limit = account.creditLimit, limit > 0 {
                                let owedAfter = account.amountOwed + amountValue
                                let utilization = min(max(owedAfter / limit, 0), 1)
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text("UTILIZATION")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.secondary)
                                    Text("\(Int(utilization * 100))%")
                                        .font(.headline)
                                }
                            }
                        }
                        .padding(15)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.indigo.opacity(0.07))
                        )
                    }

                    Button {
                        savePurchase()
                    } label: {
                        Text("Add Purchase")
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.indigo, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Add Purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.secondary)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 17)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func savePurchase() {
        guard canSave else { return }

        let cleanMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let transaction = MoneyTransaction(
            amount: amountValue,
            date: date,
            type: .expense,
            category: category,
            note: cleanNote,
            merchant: cleanMerchant
        )

        let movement = AccountMovement(
            amount: amountValue,
            date: date,
            type: .expense,
            note: cleanMerchant.isEmpty ? category.rawValue : cleanMerchant,
            linkedTransactionID: transaction.id,
            account: account
        )

        account.movements.append(movement)
        modelContext.insert(transaction)
        modelContext.insert(movement)
        try? modelContext.save()
        MoneyLedger.refreshCardReminders(account)
        dismiss()
    }
}

// MARK: - CREDIT CARD PAYMENT

struct CreditCardPaymentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \MoneyAccount.createdAt)
    private var accounts: [MoneyAccount]

    let card: MoneyAccount

    @State private var sourceAccountID: UUID?
    @State private var amount = ""
    @State private var note = ""

    private var sourceAccounts: [MoneyAccount] {
        accounts.filter { $0.id != card.id && $0.type != .creditCard }
    }

    private var sourceAccount: MoneyAccount? {
        sourceAccounts.first { $0.id == sourceAccountID }
    }

    private var amountValue: Double { MoneyInput.parse(amount) ?? 0 }

    private var canSave: Bool {
        amountValue > 0 &&
        sourceAccount != nil &&
        amountValue <= card.amountOwed + MoneyInput.epsilon
    }

    private var owedAfterPayment: Double {
        max(card.amountOwed - amountValue, 0)
    }

    private var availableAfterPayment: Double {
        guard let limit = card.creditLimit else { return 0 }
        return max(limit - owedAfterPayment, 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("PAY CREDIT CARD")
                        .font(.caption2)
                        .fontWeight(.black)
                        .tracking(2)
                        .foregroundStyle(.indigo)

                    Text(card.name)
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text("Currently owed: \(card.amountOwed.formatted(.currency(code: "CAD")))")
                        .foregroundStyle(.secondary)

                    Text("PAY FROM")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    if sourceAccounts.isEmpty {
                        Text("Add a chequing, savings, or cash account first.")
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(fieldBackground)
                    } else {
                        Picker("Source Account", selection: $sourceAccountID) {
                            Text("Choose account").tag(Optional<UUID>.none)
                            ForEach(sourceAccounts, id: \.id) { account in
                                Label(account.name, systemImage: account.type.icon)
                                    .tag(Optional(account.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(fieldBackground)
                    }

                    Text("PAYMENT AMOUNT")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("$").font(.title2)
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                    }
                    .padding()
                    .background(fieldBackground)

                    TextField("Note (optional)", text: $note)
                        .padding()
                        .background(fieldBackground)

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("OWED AFTER PAYMENT")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Text(owedAfterPayment, format: .currency(code: "CAD"))
                                .font(.headline)
                        }
                        Spacer()
                        if card.creditLimit != nil {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("AVAILABLE")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                Text(availableAfterPayment, format: .currency(code: "CAD"))
                                    .font(.headline)
                            }
                        }
                    }
                    .padding(15)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.indigo.opacity(0.07))
                    )

                    Button {
                        savePayment()
                    } label: {
                        Text("Make Payment")
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.indigo, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Make Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if sourceAccountID == nil {
                    sourceAccountID = sourceAccounts.first?.id
                }
            }
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 17)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func savePayment() {
        guard canSave, let sourceAccount else { return }

        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let outgoing = AccountMovement(
            amount: amountValue,
            type: .transferOut,
            note: cleanNote.isEmpty ? "Payment to \(card.name)" : cleanNote,
            account: sourceAccount
        )

        let incoming = AccountMovement(
            amount: amountValue,
            type: .transferIn,
            note: cleanNote.isEmpty ? "Payment from \(sourceAccount.name)" : cleanNote,
            account: card
        )

        sourceAccount.movements.append(outgoing)
        card.movements.append(incoming)
        modelContext.insert(outgoing)
        modelContext.insert(incoming)
        try? modelContext.save()

        // Paid in full: no point reminding about a zero balance.
        if card.amountOwed < MoneyInput.epsilon {
            CreditCardNotificationScheduler.removeNotifications(for: card.id)
        } else {
            MoneyLedger.refreshCardReminders(card)
        }

        dismiss()
    }
}

// MARK: - ACCOUNT PICKER

struct MoneyAccountPicker: View {
    @Query(sort: \MoneyAccount.createdAt)
    private var accounts: [MoneyAccount]

    @Binding var selectedAccountID: UUID?

    var title: String = "Account"

    var body: some View {
        Group {
            if !accounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title.uppercased())
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    Picker(title, selection: $selectedAccountID) {
                        Text("No Account")
                            .tag(Optional<UUID>.none)

                        ForEach(accounts, id: \.id) { account in
                            Label(account.name, systemImage: account.type.icon)
                                .tag(Optional(account.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 17)
                            .fill(
                                Color(
                                    uiColor: .secondarySystemGroupedBackground
                                )
                            )
                    )
                }
            }
        }
    }
}

