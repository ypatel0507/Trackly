import SwiftUI

import SwiftData

import UserNotifications

import UIKit

// MARK: - TRACKING MODELS

@Model

final class Tracker: Identifiable {

    var id: UUID

    var name: String

    var icon: String

    @Relationship(deleteRule: .cascade)

    var habits: [Habit]

    init(

        id: UUID = UUID(),

        name: String,

        icon: String,

        habits: [Habit] = []

    ) {

        self.id = id

        self.name = name

        self.icon = icon

        self.habits = habits

    }

    var orderedHabits: [Habit] {

        habits.sorted {

            $0.sortOrder < $1.sortOrder

        }

    }

}

@Model

final class Habit: Identifiable {

    var id: UUID

    var name: String

    var icon: String

    var scheduleTypeRaw: String

    var selectedWeekdaysRaw: String

    var timesPerWeek: Int

    var startDate: Date

    var sortOrder: Int

    // Optional fields keep existing SwiftData stores migration-friendly.
    var reminderEnabled: Bool?

    var reminderHour: Int?

    var reminderMinute: Int?

    @Relationship(deleteRule: .cascade)

    var completions: [HabitCompletion]

    init(

        id: UUID = UUID(),

        name: String,

        icon: String,

        scheduleType: HabitScheduleType = .everyDay,

        selectedWeekdays: Set<Int> = [],

        timesPerWeek: Int = 3,

        startDate: Date = Date(),

        sortOrder: Int = 0,

        reminderEnabled: Bool = false,

        reminderHour: Int = 20,

        reminderMinute: Int = 0,

        completions: [HabitCompletion] = []

    ) {

        self.id = id

        self.name = name

        self.icon = icon

        self.scheduleTypeRaw = scheduleType.rawValue

        self.selectedWeekdaysRaw =

            selectedWeekdays

                .sorted()

                .map(String.init)

                .joined(separator: ",")

        self.timesPerWeek = timesPerWeek

        self.startDate = Calendar.current.startOfDay(for: startDate)

        self.sortOrder = sortOrder

        self.reminderEnabled = reminderEnabled

        self.reminderHour = reminderHour

        self.reminderMinute = reminderMinute

        self.completions = completions

    }

    var scheduleType: HabitScheduleType {

        get {

            HabitScheduleType(rawValue: scheduleTypeRaw) ?? .everyDay

        }

        set {

            scheduleTypeRaw = newValue.rawValue

        }

    }

    var selectedWeekdays: Set<Int> {

        get {

            Set(

                selectedWeekdaysRaw

                    .split(separator: ",")

                    .compactMap {

                        Int($0)

                    }

            )

        }

        set {

            selectedWeekdaysRaw =

                newValue

                    .sorted()

                    .map(String.init)

                    .joined(separator: ",")

        }

    }

    func isCompleted(on date: Date) -> Bool {

        let calendar = Calendar.current

        return completions.contains {

            calendar.isDate(

                $0.date,

                inSameDayAs: date

            )

        }

    }

    func toggle(

        on date: Date,

        context: ModelContext

    ) {

        let calendar = Calendar.current

        let day = calendar.startOfDay(for: date)

        if let existing = completions.first(

            where: {

                calendar.isDate(

                    $0.date,

                    inSameDayAs: day

                )

            }

        ) {

            completions.removeAll {

                $0.id == existing.id

            }

            context.delete(existing)

        } else {

            let completion =

                HabitCompletion(date: day)

            completions.append(completion)

            context.insert(completion)

        }

        try? context.save()

    }

    func isScheduled(on date: Date) -> Bool {

        let calendar = Calendar.current

        let day =

            calendar.startOfDay(for: date)

        let start =

            calendar.startOfDay(for: startDate)

        guard day >= start else {

            return false

        }

        switch scheduleType {

        case .everyDay:

            return true

        case .specificDays:

            let weekday =

                calendar.component(

                    .weekday,

                    from: date

                )

            return selectedWeekdays.contains(weekday)

        case .timesPerWeek:

            return isTimesPerWeekDue(on: day, calendar: calendar)

        }

    }

    /// "X times per week" habits are flexible: a day only counts as
    /// scheduled (and therefore missable) when it actually matters.
    /// - A completed day always counts (so it shows and can be undone).
    /// - Today / future: shown while the weekly target isn't met yet.
    /// - Past days this week: never count as missed — the user can
    ///   still hit the target later in the week.
    /// - Past weeks: unfinished days count as missed only if the
    ///   week's target was not reached.
    private func isTimesPerWeekDue(
        on day: Date,
        calendar: Calendar
    ) -> Bool {

        if isCompleted(on: day) {
            return true
        }

        let target = max(timesPerWeek, 1)
        let today = calendar.startOfDay(for: Date())

        guard let week = calendar.dateInterval(
            of: .weekOfYear,
            for: day
        ) else {
            return true
        }

        let doneThisWeek = completions.filter {
            week.contains($0.date)
        }.count

        if day >= today {
            return doneThisWeek < target
        }

        if week.contains(today) {
            return false
        }

        return doneThisWeek < target
    }

    var scheduleDescription: String {

        switch scheduleType {

        case .everyDay:

            return "Every day"

        case .specificDays:

            let names =

                HabitWeekday.allCases

                    .filter {

                        selectedWeekdays.contains(

                            $0.rawValue

                        )

                    }

                    .map {

                        $0.shortName

                    }

            return names.isEmpty

                ? "No days selected"

                : names.joined(separator: " • ")

        case .timesPerWeek:

            return "\(timesPerWeek) times per week"

        }

    }

}

@Model

final class HabitCompletion: Identifiable {

    var id: UUID

    var date: Date

    init(

        id: UUID = UUID(),

        date: Date

    ) {

        self.id = id

        self.date = date

    }

}

@Model

final class Goal: Identifiable {

    var id: UUID

    var title: String

    var targetDate: Date

    var completed: Bool

    init(

        id: UUID = UUID(),

        title: String,

        targetDate: Date,

        completed: Bool = false

    ) {

        self.id = id

        self.title = title

        self.targetDate = targetDate

        self.completed = completed

    }

}

// MARK: - MONEY MODELS

@Model

final class MoneyTransaction: Identifiable {

    var id: UUID

    var amount: Double

    var date: Date

    var typeRaw: String

    var categoryRaw: String

    var note: String

    var merchant: String

    init(

        id: UUID = UUID(),

        amount: Double,

        date: Date = Date(),

        type: MoneyTransactionType,

        category: ExpenseCategory = .other,

        note: String = "",

        merchant: String = ""

    ) {

        self.id = id

        self.amount = amount

        self.date = date

        self.typeRaw = type.rawValue

        self.categoryRaw = category.rawValue

        self.note = note

        self.merchant = merchant

    }

    var type: MoneyTransactionType {

        get {

            MoneyTransactionType(

                rawValue: typeRaw

            ) ?? .expense

        }

        set {

            typeRaw = newValue.rawValue

        }

    }

    var category: ExpenseCategory {

        get {

            ExpenseCategory(

                rawValue: categoryRaw

            ) ?? .other

        }

        set {

            categoryRaw = newValue.rawValue

        }

    }

}

@Model

final class Paycheck: Identifiable {

    var id: UUID

    var employer: String

    var netPay: Double

    var grossPay: Double

    var deductions: Double

    var payDate: Date

    var periodStart: Date

    var periodEnd: Date

    var note: String

    init(

        id: UUID = UUID(),

        employer: String,

        netPay: Double,

        grossPay: Double = 0,

        deductions: Double = 0,

        payDate: Date = Date(),

        periodStart: Date = Date(),

        periodEnd: Date = Date(),

        note: String = ""

    ) {

        self.id = id

        self.employer = employer

        self.netPay = netPay

        self.grossPay = grossPay

        self.deductions = deductions

        self.payDate = payDate

        self.periodStart = periodStart

        self.periodEnd = periodEnd

        self.note = note

    }

}

@Model

final class SavingsGoal: Identifiable {

    var id: UUID

    var name: String

    var icon: String

    var targetAmount: Double

    var savedAmount: Double

    var targetDate: Date

    init(

        id: UUID = UUID(),

        name: String,

        icon: String = "target",

        targetAmount: Double,

        savedAmount: Double = 0,

        targetDate: Date = Date()

    ) {

        self.id = id

        self.name = name

        self.icon = icon

        self.targetAmount = targetAmount

        self.savedAmount = savedAmount

        self.targetDate = targetDate

    }

    var progress: Double {

        guard targetAmount > 0 else {

            return 0

        }

        return min(

            max(

                savedAmount / targetAmount,

                0

            ),

            1

        )

    }

}

// MARK: - ENUMS


// MARK: - TRACKING NOTIFICATIONS

struct HabitReminderSnapshot: Sendable {
    let id: UUID
    let name: String
    let scheduleTypeRaw: String
    let selectedWeekdays: Set<Int>
    let timesPerWeek: Int
    let reminderHour: Int
    let reminderMinute: Int
}

enum HabitNotificationScheduler {

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
        for habit: HabitReminderSnapshot
    ) async -> Bool {
        removeNotifications(for: habit.id)

        let granted = await ensurePermission()
        guard granted else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "Trackly Reminder"
        content.body = reminderBody(for: habit)
        content.sound = .default
        content.threadIdentifier = "trackly.habits"

        let scheduleType =
            HabitScheduleType(
                rawValue: habit.scheduleTypeRaw
            ) ?? .everyDay

        switch scheduleType {
        case .specificDays:
            for weekday in habit.selectedWeekdays.sorted() {
                var components = DateComponents()
                components.weekday = weekday
                components.hour = habit.reminderHour
                components.minute = habit.reminderMinute

                let request = UNNotificationRequest(
                    identifier:
                        notificationID(
                            habitID: habit.id,
                            suffix: "weekday-\(weekday)"
                        ),
                    content: content,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: components,
                        repeats: true
                    )
                )

                try? await UNUserNotificationCenter.current()
                    .add(request)
            }

        case .everyDay, .timesPerWeek:
            var components = DateComponents()
            components.hour = habit.reminderHour
            components.minute = habit.reminderMinute

            let request = UNNotificationRequest(
                identifier:
                    notificationID(
                        habitID: habit.id,
                        suffix: "daily"
                    ),
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: components,
                    repeats: true
                )
            )

            try? await UNUserNotificationCenter.current()
                .add(request)
        }

        return true
    }

    static func removeNotifications(
        for habitID: UUID
    ) {
        // Every possible ID is known up front ("daily" + one per
        // weekday), so remove them synchronously. The old version looked
        // them up in an async callback, which could run *after*
        // reschedule() added the new reminders and delete them too.
        let suffixes =
            ["daily"] + (1...7).map { "weekday-\($0)" }

        let ids = suffixes.map {
            notificationID(habitID: habitID, suffix: $0)
        }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    @discardableResult
    static func sendTestNotification(
        habitName: String
    ) async -> Bool {
        let granted = await ensurePermission()
        guard granted else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "Trackly Test Reminder"
        content.body =
            "Time for \(habitName). Your habit notifications are working."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier:
                "trackly.habit.test.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: 5,
                repeats: false
            )
        )

        do {
            try await UNUserNotificationCenter.current()
                .add(request)
            return true
        } catch {
            return false
        }
    }

    private static func reminderBody(
        for habit: HabitReminderSnapshot
    ) -> String {
        let scheduleType =
            HabitScheduleType(
                rawValue: habit.scheduleTypeRaw
            ) ?? .everyDay

        if scheduleType == .timesPerWeek {
            return
                "Don't forget \(habit.name). Your goal is \(habit.timesPerWeek) times this week."
        }

        return
            "Don't forget \(habit.name). A small step today keeps your streak moving."
    }

    private static func notificationID(
        habitID: UUID,
        suffix: String
    ) -> String {
        "trackly.habit.\(habitID.uuidString).\(suffix)"
    }
}

struct HabitReminderEditor: View {
    @Binding var isEnabled: Bool
    @Binding var reminderTime: Date
    let habitName: String
    let onPermissionDenied: () -> Void

    @State private var testSent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 38, height: 38)
                    .background(
                        Color.indigo.opacity(0.10),
                        in: RoundedRectangle(
                            cornerRadius: 12
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Habit Reminder")
                        .font(.headline)

                    Text(
                        "Get a notification when it's time to check in."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle(
                    "",
                    isOn: $isEnabled
                )
                .labelsHidden()
            }

            if isEnabled {
                Divider()

                DatePicker(
                    "Reminder Time",
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                )

                Button {
                    sendTest()
                } label: {
                    Label(
                        testSent
                        ? "Test Sent — Lock Your iPhone"
                        : "Send Test in 5 Seconds",
                        systemImage:
                            testSent
                            ? "checkmark.circle.fill"
                            : "bell.and.waves.left.and.right"
                    )
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.bordered)

                Text(
                    "Every Day habits remind you daily. Specific Days habits only remind you on the selected days. Times Per Week habits use a daily nudge until you reach your weekly target."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            PremiumCardBackground()
        )
    }

    private func sendTest() {
        let cleanName =
            habitName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        Task {
            let success =
                await HabitNotificationScheduler
                    .sendTestNotification(
                        habitName:
                            cleanName.isEmpty
                            ? "your habit"
                            : cleanName
                    )

            await MainActor.run {
                if success {
                    testSent = true
                } else {
                    onPermissionDenied()
                }
            }
        }
    }
}


enum HabitScheduleType:

    String,

    CaseIterable,

    Identifiable {

    case everyDay = "Every Day"

    case specificDays = "Specific Days"

    case timesPerWeek = "Times Per Week"

    var id: String {

        rawValue

    }

}

enum HabitWeekday:

    Int,

    CaseIterable,

    Identifiable {

    case sunday = 1

    case monday = 2

    case tuesday = 3

    case wednesday = 4

    case thursday = 5

    case friday = 6

    case saturday = 7

    var id: Int {

        rawValue

    }

    var shortName: String {

        switch self {

        case .sunday: return "Sun"

        case .monday: return "Mon"

        case .tuesday: return "Tue"

        case .wednesday: return "Wed"

        case .thursday: return "Thu"

        case .friday: return "Fri"

        case .saturday: return "Sat"

        }

    }

    var letter: String {

        switch self {

        case .sunday: return "S"

        case .monday: return "M"

        case .tuesday: return "T"

        case .wednesday: return "W"

        case .thursday: return "T"

        case .friday: return "F"

        case .saturday: return "S"

        }

    }

}

enum TrackerHistoryMode:

    String,

    CaseIterable,

    Identifiable {

    case week = "Week"

    case month = "Month"

    var id: String {

        rawValue

    }

}

enum InsightPeriod:

    String,

    CaseIterable,

    Identifiable {

    case week = "Week"

    case month = "Month"

    case year = "Year"

    var id: String {

        rawValue

    }

}

enum AnalyticsType:

    String,

    CaseIterable,

    Identifiable {

    case tracking = "Tracking"

    case money = "Money"

    var id: String {

        rawValue

    }

}

enum MoneyTransactionType:

    String,

    CaseIterable,

    Identifiable {

    case expense = "Expense"

    case otherIncome = "Other Income"

    var id: String {

        rawValue

    }

}

enum ExpenseCategory:

    String,

    CaseIterable,

    Identifiable {

    case food = "Food"

    case transport = "Transport"

    case shopping = "Shopping"

    case housing = "Housing"

    case bills = "Bills"

    case entertainment = "Entertainment"

    case university = "University"

    case health = "Health"

    case travel = "Travel"

    case other = "Other"

    var id: String {

        rawValue

    }

    var icon: String {

        switch self {

        case .food:

            return "fork.knife"

        case .transport:

            return "car.fill"

        case .shopping:

            return "bag.fill"

        case .housing:

            return "house.fill"

        case .bills:

            return "doc.text.fill"

        case .entertainment:

            return "gamecontroller.fill"

        case .university:

            return "graduationcap.fill"

        case .health:

            return "heart.fill"

        case .travel:

            return "airplane"

        case .other:

            return "square.grid.2x2.fill"

        }

    }

}

// MARK: - MAIN

struct ContentView: View {

    @Environment(\.modelContext)

    private var modelContext

    @Query

    private var trackers: [Tracker]

    @Query

    private var goals: [Goal]

    @AppStorage("tracklySeededV5")

    private var didSeed = false

    @State private var selectedTab = 0

    @State private var showQuickAdd = false

    var body: some View {

        Group {

            switch selectedTab {

            case 0:

                HomeView(

                    trackers: trackers,

                    goals: goals

                )

            case 1:

                TrackView(

                    trackers: trackers

                )

            case 2:

                MoneyView()

            case 3:

                InsightsView()

            default:

                HomeView(

                    trackers: trackers,

                    goals: goals

                )

            }

        }

        .safeAreaInset(

            edge: .bottom,

            spacing: 0

        ) {

            BottomNavigationContainer(

                selectedTab: $selectedTab,

                showAddMenu: $showQuickAdd

            )

        }

        .ignoresSafeArea(.keyboard)

        .sheet(

            isPresented: $showQuickAdd

        ) {

            QuickAddMenuView(

                trackers: trackers,

                selectedTab: selectedTab

            )

            .presentationDetents(

                [.medium, .large]

            )

            .presentationDragIndicator(.visible)

        }

        .task {

            seedDataIfNeeded()

        }

    }

    private func seedDataIfNeeded() {

        guard !didSeed else {

            return

        }

        let workout =

            Habit(

                name: "Workout",

                icon: "figure.run",

                sortOrder: 0

            )

        let water =

            Habit(

                name: "Drink 2L Water",

                icon: "drop.fill",

                sortOrder: 1

            )

        let protein =

            Habit(

                name: "Protein Goal",

                icon: "fork.knife",

                sortOrder: 2

            )

        let sleep =

            Habit(

                name: "Sleep 8 Hours",

                icon: "moon.fill",

                sortOrder: 3

            )

        workout.completions.append(

            HabitCompletion(

                date:

                    Calendar.current

                        .startOfDay(

                            for: Date()

                        )

            )

        )

        let fitness =

            Tracker(

                name: "Fitness",

                icon: "figure.run",

                habits: [

                    workout,

                    water,

                    protein,

                    sleep

                ]

            )

        let study =

            Habit(

                name: "Study",

                icon: "book.fill",

                sortOrder: 0

            )

        let read =

            Habit(

                name: "Read",

                icon: "text.book.closed.fill",

                sortOrder: 1

            )

        let university =

            Tracker(

                name: "University",

                icon: "book.fill",

                habits: [

                    study,

                    read

                ]

            )

        modelContext.insert(fitness)

        modelContext.insert(university)

        modelContext.insert(

            Goal(

                title: "30 Day Consistency",

                targetDate:

                    Calendar.current.date(

                        byAdding: .day,

                        value: 30,

                        to: Date()

                    ) ?? Date()

            )

        )

        try? modelContext.save()

        didSeed = true

    }

}

// MARK: - HOME

struct HomeView: View {

    let trackers: [Tracker]

    let goals: [Goal]

    @Query(sort: \MoneyAccount.createdAt)

    private var moneyAccounts: [MoneyAccount]

    @State private var selectedDate = Date()

    @State private var showTracklyBrief = false

    @State private var showSettings = false

    private var allHabits: [Habit] {

        trackers.flatMap(\.orderedHabits)

    }

    private var scheduledHabits: [Habit] {

        allHabits.filter {

            $0.isScheduled(

                on: selectedDate

            )

        }

    }

    private var completedCount: Int {

        scheduledHabits.filter {

            $0.isCompleted(

                on: selectedDate

            )

        }

        .count

    }

    private var progress: Double {

        guard !scheduledHabits.isEmpty else {

            return 0

        }

        return

            Double(completedCount)

            /

            Double(scheduledHabits.count)

    }

    private var activeGoals: Int {

        goals.filter {

            !$0.completed

        }

        .count

    }

    private var streak: Int {

        calculateCurrentStreak(

            habits: allHabits

        )

    }

    private var upcomingCreditCards: [MoneyAccount] {

        moneyAccounts

            .filter {

                $0.type == .creditCard

                    &&

                    $0.paymentDueDate != nil

            }

            .sorted {

                guard

                    let firstDate = $0.paymentDueDate,

                    let secondDate = $1.paymentDueDate

                else {

                    return false

                }

                return firstDate < secondDate

            }

    }

    private var visibleUpcomingCreditCards: [MoneyAccount] {

        Array(

            upcomingCreditCards.prefix(3)

        )

    }

    var body: some View {

        NavigationStack {

            ScrollView(

                .vertical,

                showsIndicators: true

            ) {

                VStack(

                    alignment: .leading,

                    spacing: 26

                ) {

                    HStack(

                        alignment: .top

                    ) {

                        VStack(

                            alignment: .leading,

                            spacing: 7

                        ) {

                            Text("TRACKLY")

                                .font(.caption2)

                                .fontWeight(.black)

                                .tracking(3.2)

                                .foregroundStyle(.indigo)

                            Text(greeting)

                                .font(

                                    .system(

                                        size: 31,

                                        weight: .bold,

                                        design: .rounded

                                    )

                                )

                            Label(

                                formattedToday,

                                systemImage: "calendar"

                            )

                            .font(.subheadline)

                            .foregroundStyle(.secondary)

                        }

                        Spacer()

                        HStack(spacing: 10) {

                            Button {

                                showTracklyBrief = true

                            } label: {

                                Image(

                                    systemName: "sparkles"

                                )

                                .font(

                                    .system(

                                        size: 18,

                                        weight: .semibold

                                    )

                                )

                                .foregroundStyle(.indigo)

                                .frame(

                                    width: 46,

                                    height: 46

                                )

                                .background(

                                    Color(

                                        uiColor:

                                            .secondarySystemGroupedBackground

                                    ),

                                    in: Circle()

                                )

                            }

                            .buttonStyle(

                                PremiumPressButtonStyle()

                            )

                            Button {

                                showSettings = true

                            } label: {

                                Image(

                                    systemName: "gearshape.fill"

                                )

                                .font(

                                    .system(

                                        size: 18,

                                        weight: .semibold

                                    )

                                )

                                .foregroundStyle(.indigo)

                                .frame(

                                    width: 46,

                                    height: 46

                                )

                                .background(

                                    Color(

                                        uiColor:

                                            .secondarySystemGroupedBackground

                                    ),

                                    in: Circle()

                                )

                            }

                            .buttonStyle(

                                PremiumPressButtonStyle()

                            )

                        }

                    }

                    PremiumProgressCard(

                        completed: completedCount,

                        total: scheduledHabits.count,

                        progress: progress,

                        date: selectedDate,

                        streak: streak

                    )

                    HStack(spacing: 10) {

                        HomeMiniStat(

                            icon:

                                "checkmark.circle.fill",

                            value:

                                "\(completedCount)",

                            label: "Done"

                        )

                        HomeMiniStat(

                            icon:

                                "square.grid.2x2.fill",

                            value:

                                "\(trackers.count)",

                            label: "Trackers"

                        )

                        HomeMiniStat(

                            icon: "target",

                            value:

                                "\(activeGoals)",

                            label: "Goals"

                        )

                    }

                    if !visibleUpcomingCreditCards.isEmpty {

                        VStack(

                            alignment: .leading,

                            spacing: 12

                        ) {

                            HomeSectionHeader(

                                title: "Upcoming payments",

                                subtitle:

                                    paymentSectionSubtitle

                            )

                            VStack(spacing: 10) {

                                ForEach(

                                    visibleUpcomingCreditCards,

                                    id: \.id

                                ) { card in

                                    NavigationLink {

                                        MoneyAccountDetailView(

                                            account: card

                                        )

                                    } label: {

                                        HomeCreditCardPaymentCard(

                                            account: card

                                        )

                                    }

                                    .buttonStyle(

                                        PremiumPressButtonStyle()

                                    )

                                }

                            }

                        }

                    }

                    VStack(

                        alignment: .leading,

                        spacing: 12

                    ) {

                        HomeSectionHeader(

                            title: "Your week",

                            subtitle:

                                "Tap a date to review your day"

                        )

                        CompactWeekCalendar(

                            selectedDate:

                                $selectedDate,

                            trackers:

                                trackers

                        )

                    }

                    VStack(

                        alignment: .leading,

                        spacing: 12

                    ) {

                        HomeSectionHeader(

                            title:

                                Calendar.current.isDateInToday(

                                    selectedDate

                                )

                                ? "Today"

                                : formattedDate(

                                    selectedDate

                                ),

                            subtitle:

                                "\(completedCount) of \(scheduledHabits.count) completed"

                        )

                        DailyHabitList(

                            trackers:

                                trackers,

                            selectedDate:

                                selectedDate

                        )

                    }

                    VStack(

                        alignment: .leading,

                        spacing: 12

                    ) {

                        HomeSectionHeader(

                            title:

                                "Your trackers",

                            subtitle:

                                "Everything you're building"

                        )

                        VStack(spacing: 12) {

                            ForEach(

                                trackers,

                                id: \.id

                            ) { tracker in

                                NavigationLink {

                                    TrackerDetailView(

                                        tracker:

                                            tracker

                                    )

                                } label: {

                                    TrackerCard(

                                        tracker:

                                            tracker,

                                        date:

                                            selectedDate

                                    )

                                }

                                .buttonStyle(

                                    PremiumPressButtonStyle()

                                )

                            }

                        }

                    }

                    VStack(

                        alignment: .leading,

                        spacing: 12

                    ) {

                        HomeSectionHeader(

                            title: "Goals",

                            subtitle:

                                activeGoals == 1

                                ? "1 active goal"

                                : "\(activeGoals) active goals"

                        )

                        GoalListView(

                            goals: goals

                        )

                    }

                }

                .padding(.horizontal, 20)

                .padding(.top, 20)

                .padding(.bottom, 150)

            }

            .background(

                Color(

                    uiColor:

                        .systemGroupedBackground

                )

                .ignoresSafeArea()

            )

            .toolbar(

                .hidden,

                for: .navigationBar

            )

            .sheet(

                isPresented:

                    $showTracklyBrief

            ) {

                TracklyBriefView(

                    trackers: trackers,

                    goals: goals

                )

                .presentationDetents(

                    [.medium, .large]

                )

                .presentationDragIndicator(.visible)

            }

            .sheet(

                isPresented:

                    $showSettings

            ) {

                TracklySettingsView()

            }

        }

    }

    private var paymentSectionSubtitle: String {

        let overdueCount =

            upcomingCreditCards.filter {

                guard let dueDate = $0.paymentDueDate else {

                    return false

                }

                return

                    Calendar.current.startOfDay(

                        for: dueDate

                    )

                    <

                    Calendar.current.startOfDay(

                        for: Date()

                    )

            }

            .count

        if overdueCount > 0 {

            return overdueCount == 1

                ? "1 payment needs attention"

                : "\(overdueCount) payments need attention"

        }

        return upcomingCreditCards.count == 1

            ? "1 card payment coming up"

            : "\(upcomingCreditCards.count) card payments coming up"

    }

    private var greeting: String {

        let hour =

            Calendar.current.component(

                .hour,

                from: Date()

            )

        if hour < 12 {

            return "Good morning 👋"

        }

        if hour < 17 {

            return "Good afternoon 👋"

        }

        return "Good evening 👋"

    }

    private var formattedToday: String {

        let formatter = DateFormatter()

        formatter.dateFormat =

            "EEEE, MMMM d"

        return formatter.string(

            from: Date()

        )

    }

    private func formattedDate(

        _ date: Date

    ) -> String {

        let formatter = DateFormatter()

        formatter.dateFormat =

            "EEEE, MMM d"

        return formatter.string(

            from: date

        )

    }

}

// MARK: - HOME CREDIT CARD PAYMENT

struct HomeCreditCardPaymentCard: View {

    let account: MoneyAccount

    private var dueDate: Date? {

        account.paymentDueDate

    }

    private var daysUntilDue: Int? {

        guard let dueDate else {

            return nil

        }

        let calendar = Calendar.current

        return calendar.dateComponents(

            [.day],

            from:

                calendar.startOfDay(

                    for: Date()

                ),

            to:

                calendar.startOfDay(

                    for: dueDate

                )

        )

        .day

    }

    private var statusText: String {

        guard let daysUntilDue else {

            return "Due date not set"

        }

        if daysUntilDue < 0 {

            let overdueDays =

                abs(daysUntilDue)

            return overdueDays == 1

                ? "1 day overdue"

                : "\(overdueDays) days overdue"

        }

        if daysUntilDue == 0 {

            return "Due today"

        }

        if daysUntilDue == 1 {

            return "Due tomorrow"

        }

        return "Due in \(daysUntilDue) days"

    }

    private var statusColor: Color {

        guard let daysUntilDue else {

            return .secondary

        }

        if daysUntilDue < 0 {

            return .red

        }

        if daysUntilDue <= 3 {

            return .orange

        }

        return .indigo

    }

    private var paymentAmount: Double {

        if let minimum = account.minimumPaymentDue,

           minimum > 0 {

            return minimum

        }

        if let statement = account.statementBalance,

           statement > 0 {

            return statement

        }

        return account.amountOwed

    }

    private var paymentLabel: String {

        if let minimum = account.minimumPaymentDue,

           minimum > 0 {

            return "Minimum due"

        }

        if let statement = account.statementBalance,

           statement > 0 {

            return "Statement"

        }

        return "Amount owed"

    }

    var body: some View {

        HStack(spacing: 14) {

            Image(

                systemName:

                    "creditcard.fill"

            )

            .font(

                .system(

                    size: 18,

                    weight: .semibold

                )

            )

            .foregroundStyle(.indigo)

            .frame(

                width: 44,

                height: 44

            )

            .background(

                Color.indigo.opacity(0.10),

                in: RoundedRectangle(

                    cornerRadius: 14

                )

            )

            VStack(

                alignment: .leading,

                spacing: 5

            ) {

                Text(account.name)

                    .font(.headline)

                    .foregroundStyle(.primary)

                HStack(spacing: 6) {

                    if let dueDate {

                        Text(

                            dueDate.formatted(

                                date: .abbreviated,

                                time: .omitted

                            )

                        )

                        Text("•")

                    }

                    Text(statusText)

                        .fontWeight(.semibold)

                        .foregroundStyle(statusColor)

                }

                .font(.caption)

            }

            Spacer()

            VStack(

                alignment: .trailing,

                spacing: 4

            ) {

                Text(

                    paymentAmount,

                    format:

                        .currency(

                            code: "CAD"

                        )

                )

                .font(

                    .system(

                        size: 16,

                        weight: .bold,

                        design: .rounded

                    )

                )

                .foregroundStyle(.primary)

                Text(paymentLabel)

                    .font(.caption2)

                    .foregroundStyle(.secondary)

            }

            Image(

                systemName:

                    "chevron.right"

            )

            .font(.caption)

            .fontWeight(.bold)

            .foregroundStyle(.tertiary)

        }

        .padding(15)

        .background(

            PremiumCardBackground()

        )

    }

}

// MARK: - TRACKLY BRIEF

struct TracklyBriefView: View {

    @Environment(\.dismiss)

    private var dismiss

    let trackers: [Tracker]

    let goals: [Goal]

    private var habits: [Habit] {

        trackers.flatMap(\.orderedHabits)

    }

    private var todayHabits: [Habit] {

        habits.filter {

            $0.isScheduled(

                on: Date()

            )

        }

    }

    private var completedToday: Int {

        todayHabits.filter {

            $0.isCompleted(

                on: Date()

            )

        }

        .count

    }

    private var progress: Double {

        guard !todayHabits.isEmpty else {

            return 0

        }

        return

            Double(completedToday)

            /

            Double(todayHabits.count)

    }

    private var remaining: Int {

        max(

            todayHabits.count

            -

            completedToday,

            0

        )

    }

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(

                    alignment: .leading,

                    spacing: 22

                ) {

                    VStack(

                        alignment: .leading,

                        spacing: 6

                    ) {

                        Text("TRACKLY BRIEF")

                            .font(.caption2)

                            .fontWeight(.black)

                            .tracking(3)

                            .foregroundStyle(.indigo)

                        Text(

                            "Your day at a glance"

                        )

                        .font(

                            .system(

                                size: 28,

                                weight: .bold,

                                design: .rounded

                            )

                        )

                        Text(briefMessage)

                            .foregroundStyle(.secondary)

                    }

                    HStack(spacing: 18) {

                        ProgressRing(

                            progress: progress,

                            size: 86,

                            lineWidth: 9

                        )

                        VStack(

                            alignment: .leading,

                            spacing: 5

                        ) {

                            Text("Today")

                                .font(.headline)

                            Text(

                                "\(completedToday) of \(todayHabits.count) completed"

                            )

                            .foregroundStyle(.secondary)

                            Text(

                                remaining == 0 &&

                                !todayHabits.isEmpty

                                ? "Everything done ✨"

                                : "\(remaining) remaining"

                            )

                            .font(.caption)

                            .fontWeight(.semibold)

                            .foregroundStyle(

                                remaining == 0

                                ? .green

                                : .indigo

                            )

                        }

                        Spacer()

                    }

                    .padding(18)

                    .background(

                        PremiumCardBackground()

                    )

                    LazyVGrid(

                        columns: [

                            GridItem(.flexible()),

                            GridItem(.flexible())

                        ],

                        spacing: 12

                    ) {

                        BriefStatCard(

                            icon: "flame.fill",

                            value:

                                "\(calculateCurrentStreak(habits: habits))",

                            title: "Day streak"

                        )

                        BriefStatCard(

                            icon: "target",

                            value:

                                "\(goals.filter { !$0.completed }.count)",

                            title: "Active goals"

                        )

                        BriefStatCard(

                            icon:

                                "checkmark.circle.fill",

                            value:

                                "\(completedToday)",

                            title: "Done today"

                        )

                        BriefStatCard(

                            icon:

                                "square.grid.2x2.fill",

                            value:

                                "\(trackers.count)",

                            title: "Trackers"

                        )

                    }

                    if remaining > 0 {

                        HomeSectionHeader(

                            title: "Still to do",

                            subtitle:

                                "Your remaining habits today"

                        )

                        VStack(spacing: 10) {

                            ForEach(

                                todayHabits.filter {

                                    !$0.isCompleted(

                                        on: Date()

                                    )

                                },

                                id: \.id

                            ) { habit in

                                HStack(spacing: 12) {

                                    Image(

                                        systemName:

                                            habit.icon

                                    )

                                    .foregroundStyle(.indigo)

                                    .frame(

                                        width: 40,

                                        height: 40

                                    )

                                    .background(

                                        Color.indigo.opacity(

                                            0.09

                                        ),

                                        in:

                                            RoundedRectangle(

                                                cornerRadius: 12

                                            )

                                    )

                                    Text(

                                        habit.name

                                    )

                                    .fontWeight(.semibold)

                                    Spacer()

                                    Image(

                                        systemName:

                                            "circle"

                                    )

                                    .foregroundStyle(.secondary)

                                }

                                .padding(14)

                                .background(

                                    PremiumCardBackground()

                                )

                            }

                        }

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

            .navigationTitle("Brief")

            .navigationBarTitleDisplayMode(.inline)

            .toolbar {

                ToolbarItem(

                    placement:

                        .topBarTrailing

                ) {

                    Button("Done") {

                        dismiss()

                    }

                }

            }

        }

    }

    private var briefMessage: String {

        if todayHabits.isEmpty {

            return "Nothing is scheduled today."

        }

        if progress >= 1 {

            return "Perfect day. Everything is complete."

        }

        if progress >= 0.75 {

            return "You're almost finished with today's plan."

        }

        if progress >= 0.40 {

            return "You're building solid momentum."

        }

        return "You've got room to make progress today."

    }

}

// MARK: - HOME WEEK

struct CompactWeekCalendar: View {

    @Binding var selectedDate: Date

    let trackers: [Tracker]

    @State private var anchorDate =

        Date()

    private let calendar =

        Calendar.current

    private var dates: [Date] {

        let start =

            calendar.dateInterval(

                of: .weekOfYear,

                for: anchorDate

            )?.start

            ??

            calendar.startOfDay(

                for: anchorDate

            )

        return (0..<7).compactMap {

            calendar.date(

                byAdding: .day,

                value: $0,

                to: start

            )

        }

    }

    var body: some View {

        VStack(spacing: 15) {

            HStack {

                Button {

                    move(-1)

                } label: {

                    SmallCircleButton(

                        icon:

                            "chevron.left"

                    )

                }

                Spacer()

                Text(weekTitle)

                    .font(

                        .system(

                            size: 15,

                            weight: .bold,

                            design: .rounded

                        )

                    )

                Spacer()

                Button {

                    move(1)

                } label: {

                    SmallCircleButton(

                        icon:

                            "chevron.right"

                    )

                }

            }

            HStack(spacing: 5) {

                ForEach(

                    dates,

                    id: \.self

                ) { date in

                    WeekCalendarDay(

                        date: date,

                        selectedDate:

                            selectedDate,

                        completion:

                            completion(

                                on: date

                            )

                    ) {

                        selectedDate =

                            date

                    }

                }

            }

        }

        .padding(16)

        .background(

            PremiumCardBackground(

                cornerRadius: 24

            )

        )

        .onAppear {

            anchorDate =

                selectedDate

        }

    }

    private var weekTitle: String {

        guard

            let first = dates.first,

            let last = dates.last

        else {

            return ""

        }

        let formatter = DateFormatter()

        formatter.dateFormat = "MMM d"

        return

            "\(formatter.string(from: first)) – \(formatter.string(from: last))"

    }

    private func move(

        _ direction: Int

    ) {

        if let next =

            calendar.date(

                byAdding: .day,

                value:

                    direction * 7,

                to: anchorDate

            ) {

            anchorDate = next

            selectedDate = next

        }

    }

    private func completion(

        on date: Date

    ) -> Double {

        let habits =

            trackers

                .flatMap(\.orderedHabits)

                .filter {

                    $0.isScheduled(

                        on: date

                    )

                }

        guard !habits.isEmpty else {

            return 0

        }

        let done =

            habits.filter {

                $0.isCompleted(

                    on: date

                )

            }

            .count

        return

            Double(done)

            /

            Double(habits.count)

    }

}

struct WeekCalendarDay: View {

    let date: Date

    let selectedDate: Date

    let completion: Double

    let action: () -> Void

    private let calendar =

        Calendar.current

    var body: some View {

        Button(

            action: action

        ) {

            VStack(spacing: 7) {

                Text(weekday)

                    .font(

                        .system(

                            size: 9,

                            weight: .bold

                        )

                    )

                    .foregroundStyle(

                        selected

                        ? .indigo

                        : .secondary

                    )

                ZStack {

                    Circle()

                        .stroke(

                            Color.primary.opacity(

                                0.08

                            ),

                            lineWidth: 4

                        )

                    Circle()

                        .trim(

                            from: 0,

                            to:

                                min(

                                    max(

                                        completion,

                                        0

                                    ),

                                    1

                                )

                        )

                        .stroke(

                            .indigo,

                            style:

                                StrokeStyle(

                                    lineWidth: 4,

                                    lineCap: .round

                                )

                        )

                        .rotationEffect(

                            .degrees(-90)

                        )

                    Text(

                        "\(calendar.component(.day, from: date))"

                    )

                    .font(

                        .system(

                            size: 11,

                            weight:

                                selected ||

                                calendar.isDateInToday(

                                    date

                                )

                                ? .bold

                                : .semibold,

                            design: .rounded

                        )

                    )

                }

                .frame(

                    width: 34,

                    height: 34

                )

                Circle()

                    .fill(

                        calendar.isDateInToday(

                            date

                        )

                        ? Color.indigo

                        : Color.clear

                    )

                    .frame(

                        width: 4,

                        height: 4

                    )

            }

            .frame(

                maxWidth: .infinity

            )

            .padding(.vertical, 7)

            .background(

                selected

                ? Color.indigo.opacity(

                    0.08

                )

                : Color.clear,

                in:

                    RoundedRectangle(

                        cornerRadius: 14

                    )

            )

        }

        .buttonStyle(.plain)

    }

    private var selected: Bool {

        calendar.isDate(

            date,

            inSameDayAs:

                selectedDate

        )

    }

    private var weekday: String {

        let formatter = DateFormatter()

        formatter.dateFormat = "EE"

        return formatter

            .string(from: date)

            .uppercased()

    }

}

// MARK: - DAILY HABITS

struct DailyHabitList: View {

    @Environment(\.modelContext)

    private var modelContext

    let trackers: [Tracker]

    let selectedDate: Date

    private var items:

        [(Tracker, Habit)] {

        var result:

            [(Tracker, Habit)] = []

        for tracker in trackers {

            for habit in

                tracker.orderedHabits {

                if habit.isScheduled(

                    on: selectedDate

                ) {

                    result.append(

                        (

                            tracker,

                            habit

                        )

                    )

                }

            }

        }

        return result

    }

    var body: some View {

        VStack(spacing: 10) {

            if items.isEmpty {

                EmptyCard(

                    icon:

                        "checkmark.circle",

                    title:

                        "Nothing scheduled",

                    subtitle:

                        "Enjoy the free space in your day."

                )

            } else {

                ForEach(

                    items,

                    id: \.1.id

                ) { item in

                    PremiumHabitRow(

                        trackerName:

                            item.0.name,

                        habit:

                            item.1,

                        selectedDate:

                            selectedDate

                    ) {

                        item.1.toggle(

                            on: selectedDate,

                            context:

                                modelContext

                        )

                    }

                }

            }

        }

    }

}

struct PremiumHabitRow: View {

    let trackerName: String

    let habit: Habit

    let selectedDate: Date

    let action: () -> Void

    private var completed: Bool {

        habit.isCompleted(

            on: selectedDate

        )

    }

    var body: some View {

        Button(

            action: action

        ) {

            HStack(spacing: 14) {

                Image(

                    systemName:

                        habit.icon

                )

                .font(

                    .system(

                        size: 16,

                        weight: .semibold

                    )

                )

                .foregroundStyle(

                    completed

                    ? .white

                    : .indigo

                )

                .frame(

                    width: 46,

                    height: 46

                )

                .background(

                    completed

                    ? Color.indigo

                    : Color.indigo.opacity(

                        0.09

                    ),

                    in:

                        RoundedRectangle(

                            cornerRadius: 14

                        )

                )

                VStack(

                    alignment: .leading,

                    spacing: 4

                ) {

                    Text(

                        habit.name

                    )

                    .font(

                        .system(

                            size: 16,

                            weight: .semibold,

                            design: .rounded

                        )

                    )

                    .foregroundStyle(.primary)

                    Text(

                        trackerName

                    )

                    .font(.caption)

                    .foregroundStyle(.secondary)

                }

                Spacer()

                Image(

                    systemName:

                        completed

                        ? "checkmark.circle.fill"

                        : "circle"

                )

                .font(.title3)

                .foregroundStyle(

                    completed

                    ? .indigo

                    : .secondary

                )

            }

            .padding(15)

            .background(

                PremiumCardBackground()

            )

        }

        .buttonStyle(

            PremiumPressButtonStyle()

        )

    }

}

// MARK: - GOALS

struct GoalListView: View {

    @Environment(\.modelContext)

    private var modelContext

    let goals: [Goal]

    var body: some View {

        VStack(spacing: 10) {

            if goals.isEmpty {

                EmptyCard(

                    icon: "target",

                    title:

                        "No goals yet",

                    subtitle:

                        "Tap + to create your first goal."

                )

            } else {

                ForEach(

                    goals,

                    id: \.id

                ) { goal in

                    HStack(spacing: 14) {

                        Button {

                            goal.completed.toggle()

                            try? modelContext.save()

                        } label: {

                            Image(

                                systemName:

                                    goal.completed

                                    ? "checkmark.circle.fill"

                                    : "target"

                            )

                            .font(.title3)

                            .foregroundStyle(

                                goal.completed

                                ? .green

                                : .indigo

                            )

                        }

                        VStack(

                            alignment: .leading,

                            spacing: 4

                        ) {

                            Text(

                                goal.title

                            )

                            .fontWeight(.semibold)

                            .strikethrough(

                                goal.completed

                            )

                            Text(

                                formattedDate(

                                    goal.targetDate

                                )

                            )

                            .font(.caption)

                            .foregroundStyle(.secondary)

                        }

                        Spacer()

                        Button(

                            role: .destructive

                        ) {

                            modelContext.delete(

                                goal

                            )

                            try? modelContext.save()

                        } label: {

                            Image(

                                systemName:

                                    "trash"

                            )

                            .foregroundStyle(.secondary)

                        }

                    }

                    .padding(15)

                    .background(

                        PremiumCardBackground()

                    )

                }

            }

        }

    }

    private func formattedDate(

        _ date: Date

    ) -> String {

        let formatter = DateFormatter()

        formatter.dateFormat =

            "MMM d, yyyy"

        return formatter.string(

            from: date

        )

    }

}

// MARK: - TRACKER CARD

struct TrackerCard: View {

    let tracker: Tracker

    let date: Date

    private var scheduled:

        [Habit] {

        tracker.orderedHabits.filter {

            $0.isScheduled(

                on: date

            )

        }

    }

    private var progress: Double {

        guard !scheduled.isEmpty else {

            return 0

        }

        let completed =

            scheduled.filter {

                $0.isCompleted(

                    on: date

                )

            }

            .count

        return

            Double(completed)

            /

            Double(scheduled.count)

    }

    var body: some View {

        HStack(spacing: 15) {

            TrackerIcon(

                icon: tracker.icon,

                size: 52

            )

            VStack(

                alignment: .leading,

                spacing: 8

            ) {

                HStack {

                    Text(

                        tracker.name

                    )

                    .font(

                        .system(

                            size: 16,

                            weight: .bold,

                            design: .rounded

                        )

                    )

                    Spacer()

                    Text(

                        "\(Int(progress * 100))%"

                    )

                    .font(.caption)

                    .fontWeight(.bold)

                    .foregroundStyle(.indigo)

                }

                Text(

                    "\(tracker.habits.count) habits"

                )

                .font(.caption)

                .foregroundStyle(.secondary)

                ProgressView(

                    value: progress

                )

                .tint(.indigo)

            }

            Image(

                systemName:

                    "chevron.right"

            )

            .font(.caption)

            .foregroundStyle(.tertiary)

        }

        .padding(16)

        .background(

            PremiumCardBackground()

        )

    }

}

// MARK: - TRACK TAB

struct TrackView: View {

    let trackers: [Tracker]

    @State private var showCreateTracker =

        false

    var body: some View {

        NavigationStack {

            ScrollView(

                .vertical,

                showsIndicators: false

            ) {

                VStack(

                    alignment: .leading,

                    spacing: 24

                ) {

                    VStack(

                        alignment: .leading,

                        spacing: 7

                    ) {

                        Text("TRACK")

                            .font(.caption2)

                            .fontWeight(.black)

                            .tracking(3.2)

                            .foregroundStyle(.indigo)

                        Text(

                            "Your trackers"

                        )

                        .font(

                            .system(

                                size: 31,

                                weight: .bold,

                                design: .rounded

                            )

                        )

                        Text(

                            "Build systems for the things that matter."

                        )

                        .foregroundStyle(.secondary)

                    }

                    if trackers.isEmpty {

                        EmptyCard(

                            icon:

                                "square.grid.2x2",

                            title:

                                "Create your first tracker",

                            subtitle:

                                "Fitness, study, reading or any routine."

                        )

                    } else {

                        ForEach(

                            trackers,

                            id: \.id

                        ) { tracker in

                            NavigationLink {

                                TrackerDetailView(

                                    tracker:

                                        tracker

                                )

                            } label: {

                                TrackerCard(

                                    tracker:

                                        tracker,

                                    date:

                                        Date()

                                )

                            }

                            .buttonStyle(

                                PremiumPressButtonStyle()

                            )

                        }

                    }

                    Button {

                        showCreateTracker =

                            true

                    } label: {

                        Label(

                            "Create New Tracker",

                            systemImage: "plus"

                        )

                        .fontWeight(.semibold)

                        .foregroundStyle(.indigo)

                        .frame(

                            maxWidth: .infinity

                        )

                        .frame(height: 56)

                        .background(

                            Color.indigo.opacity(

                                0.09

                            ),

                            in:

                                RoundedRectangle(

                                    cornerRadius: 19

                                )

                        )

                    }

                }

                .padding(.horizontal, 20)

                .padding(.top, 20)

                .padding(.bottom, 28)

            }

            .background(

                Color(

                    uiColor:

                        .systemGroupedBackground

                )

            )

            .toolbar(

                .hidden,

                for: .navigationBar

            )

            .sheet(

                isPresented:

                    $showCreateTracker

            ) {

                CreateTrackerView()

                    .presentationDetents(

                        [.large]

                    )

            }

        }

    }

}

// MARK: - TRACKER DETAIL

struct TrackerDetailView: View {

    @Environment(\.modelContext)

    private var modelContext

    @Environment(\.dismiss)

    private var dismiss

    @Bindable var tracker: Tracker

    @State private var mode:

        TrackerHistoryMode =

        .week

    @State private var selectedDate =

        Date()

    @State private var weekStart =

        Calendar.current

            .dateInterval(

                of: .weekOfYear,

                for: Date()

            )?

            .start

        ?? Date()

    @State private var displayedMonth =

        Date()

    @State private var showAddHabit =

        false

    @State private var showEditTracker =

        false

    @State private var showManageHabits =

        false

    @State private var deleteAlert =

        false

    private var scheduled: [Habit] {

        tracker.orderedHabits.filter {

            $0.isScheduled(

                on: selectedDate

            )

        }

    }

    private var completed: Int {

        scheduled.filter {

            $0.isCompleted(

                on: selectedDate

            )

        }

        .count

    }

    private var progress: Double {

        guard !scheduled.isEmpty else {

            return 0

        }

        return

            Double(completed)

            /

            Double(scheduled.count)

    }

    var body: some View {

        ScrollView(

            .vertical,

            showsIndicators: false

        ) {

            VStack(

                alignment: .leading,

                spacing: 22

            ) {

                HStack(spacing: 15) {

                    TrackerIcon(

                        icon: tracker.icon,

                        size: 60

                    )

                    VStack(

                        alignment: .leading,

                        spacing: 4

                    ) {

                        Text(

                            tracker.name

                        )

                        .font(

                            .system(

                                size: 24,

                                weight: .bold,

                                design: .rounded

                            )

                        )

                        Text(

                            "\(tracker.habits.count) habits"

                        )

                        .foregroundStyle(.secondary)

                    }

                    Spacer()

                    Menu {

                        Button {

                            showEditTracker =

                                true

                        } label: {

                            Label(

                                "Edit Tracker",

                                systemImage:

                                    "pencil"

                            )

                        }

                        Button {

                            showManageHabits =

                                true

                        } label: {

                            Label(

                                "Manage Habits",

                                systemImage:

                                    "list.bullet"

                            )

                        }

                        Divider()

                        Button(

                            role: .destructive

                        ) {

                            deleteAlert =

                                true

                        } label: {

                            Label(

                                "Delete Tracker",

                                systemImage:

                                    "trash"

                            )

                        }

                    } label: {

                        Image(

                            systemName:

                                "ellipsis"

                        )

                        .frame(

                            width: 42,

                            height: 42

                        )

                        .background(

                            Color.primary.opacity(

                                0.05

                            ),

                            in: Circle()

                        )

                    }

                }

                Picker(

                    "History",

                    selection:

                        $mode

                ) {

                    ForEach(

                        TrackerHistoryMode

                            .allCases

                    ) { option in

                        Text(

                            option.rawValue

                        )

                        .tag(option)

                    }

                }

                .pickerStyle(.segmented)

                if mode == .week {

                    WeekNavigationHeader(

                        weekStart:

                            $weekStart

                    )

                    WeeklyTrackerGrid(

                        tracker:

                            tracker,

                        weekStart:

                            weekStart,

                        selectedDate:

                            $selectedDate

                    )

                } else {

                    MonthTrackerHeatmap(

                        tracker:

                            tracker,

                        displayedMonth:

                            $displayedMonth,

                        selectedDate:

                            $selectedDate

                    )

                }

                HomeSectionHeader(

                    title:

                        "Selected day",

                    subtitle:

                        dateText(

                            selectedDate

                        )

                )

                SelectedTrackerDayCard(

                    date:

                        selectedDate,

                    completed:

                        completed,

                    total:

                        scheduled.count,

                    progress:

                        progress

                )

                HStack {

                    HomeSectionHeader(

                        title:

                            "Habits",

                        subtitle:

                            "\(tracker.habits.count) total"

                    )

                    Spacer()

                    Button(

                        "Manage"

                    ) {

                        showManageHabits =

                            true

                    }

                    .font(.caption)

                    .fontWeight(.bold)

                    .foregroundStyle(.indigo)

                }

                ForEach(

                    tracker.orderedHabits,

                    id: \.id

                ) { habit in

                    NavigationLink {

                        EditHabitView(

                            habit:

                                habit

                        )

                    } label: {

                        HStack(spacing: 13) {

                            Image(

                                systemName:

                                    habit.icon

                            )

                            .foregroundStyle(.indigo)

                            .frame(

                                width: 44,

                                height: 44

                            )

                            .background(

                                Color.indigo.opacity(

                                    0.09

                                ),

                                in:

                                    RoundedRectangle(

                                        cornerRadius: 13

                                    )

                            )

                            VStack(

                                alignment: .leading,

                                spacing: 4

                            ) {

                                Text(

                                    habit.name

                                )

                                .fontWeight(.semibold)

                                .foregroundStyle(.primary)

                                Text(

                                    habit.scheduleDescription

                                )

                                .font(.caption)

                                .foregroundStyle(.secondary)

                            }

                            Spacer()

                            Image(

                                systemName:

                                    "chevron.right"

                            )

                            .foregroundStyle(.tertiary)

                        }

                        .padding(14)

                        .background(

                            PremiumCardBackground()

                        )

                    }

                    .buttonStyle(

                        PremiumPressButtonStyle()

                    )

                }

                Button {

                    showAddHabit =

                        true

                } label: {

                    Label(

                        "Add Habit",

                        systemImage: "plus"

                    )

                    .fontWeight(.semibold)

                    .foregroundStyle(.indigo)

                    .frame(

                        maxWidth: .infinity

                    )

                    .frame(height: 54)

                    .background(

                        Color.indigo.opacity(

                            0.09

                        ),

                        in:

                            RoundedRectangle(

                                cornerRadius: 18

                            )

                    )

                }

            }

            .padding(20)

            .padding(.bottom, 30)

        }

        .background(

            Color(

                uiColor:

                    .systemGroupedBackground

            )

        )

        .navigationTitle(

            tracker.name

        )

        .navigationBarTitleDisplayMode(.inline)

        .sheet(

            isPresented:

                $showAddHabit

        ) {

            AddHabitView(

                tracker:

                    tracker

            )

        }

        .sheet(

            isPresented:

                $showEditTracker

        ) {

            EditTrackerView(

                tracker:

                    tracker

            )

        }

        .sheet(

            isPresented:

                $showManageHabits

        ) {

            ManageHabitsView(

                tracker:

                    tracker

            )

        }

        .alert(

            "Delete \(tracker.name)?",

            isPresented:

                $deleteAlert

        ) {

            Button(

                "Cancel",

                role: .cancel

            ) {}

            Button(

                "Delete",

                role: .destructive

            ) {

                // Cancel reminders for every habit in this tracker,
                // otherwise they keep firing after it's gone.
                for habit in tracker.habits {
                    HabitNotificationScheduler
                        .removeNotifications(for: habit.id)
                }

                let trackerToDelete = tracker
                let context = modelContext

                // Leave the screen before deleting so the detail view
                // never renders a deleted SwiftData model.
                dismiss()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    context.delete(trackerToDelete)
                    try? context.save()
                }

            }

        } message: {

            Text(

                "This permanently deletes the tracker and its history."

            )

        }

    }

    private func dateText(

        _ date: Date

    ) -> String {

        let formatter = DateFormatter()

        formatter.dateFormat =

            "EEEE, MMM d"

        return formatter.string(

            from: date

        )

    }

}

// MARK: - TRACK CALENDAR

struct WeekNavigationHeader: View {

    @Binding var weekStart: Date

    private let calendar =

        Calendar.current

    var body: some View {

        HStack {

            Button {

                move(-1)

            } label: {

                SmallCircleButton(

                    icon:

                        "chevron.left"

                )

            }

            Spacer()

            Text(title)

                .font(.headline)

            Spacer()

            Button {

                move(1)

            } label: {

                SmallCircleButton(

                    icon:

                        "chevron.right"

                )

            }

        }

    }

    private var title: String {

        let formatter = DateFormatter()

        formatter.dateFormat = "MMM d"

        let end =

            calendar.date(

                byAdding: .day,

                value: 6,

                to: weekStart

            ) ?? weekStart

        return

            "\(formatter.string(from: weekStart)) – \(formatter.string(from: end))"

    }

    private func move(

        _ direction: Int

    ) {

        if let date =

            calendar.date(

                byAdding: .day,

                value:

                    direction * 7,

                to: weekStart

            ) {

            weekStart = date

        }

    }

}

struct WeeklyTrackerGrid: View {

    @Environment(\.modelContext)

    private var modelContext

    let tracker: Tracker

    let weekStart: Date

    @Binding var selectedDate: Date

    private let calendar =

        Calendar.current

    private var dates: [Date] {

        (0..<7).compactMap {

            calendar.date(

                byAdding: .day,

                value: $0,

                to: weekStart

            )

        }

    }

    var body: some View {

        ScrollView(

            .horizontal,

            showsIndicators: false

        ) {

            VStack(spacing: 8) {

                HStack(spacing: 7) {

                    Text("Habit")

                        .font(.caption)

                        .fontWeight(.bold)

                        .frame(

                            width: 110,

                            alignment: .leading

                        )

                    ForEach(

                        dates,

                        id: \.self

                    ) { date in

                        VStack(spacing: 3) {

                            Text(

                                weekday(

                                    date

                                )

                            )

                            .font(.caption2)

                            Text(

                                "\(calendar.component(.day, from: date))"

                            )

                            .font(.caption)

                            .fontWeight(.bold)

                        }

                        .frame(

                            width: 42,

                            height: 48

                        )

                    }

                }

                ForEach(

                    tracker.orderedHabits,

                    id: \.id

                ) { habit in

                    HStack(spacing: 7) {

                        Text(

                            habit.name

                        )

                        .font(.caption)

                        .fontWeight(.semibold)

                        .lineLimit(1)

                        .frame(

                            width: 110,

                            alignment: .leading

                        )

                        ForEach(

                            dates,

                            id: \.self

                        ) { date in

                            Button {

                                guard habit.isScheduled(

                                    on: date

                                ) else {

                                    return

                                }

                                habit.toggle(

                                    on: date,

                                    context:

                                        modelContext

                                )

                                selectedDate =

                                    date

                            } label: {

                                Image(

                                    systemName:

                                        !habit.isScheduled(

                                            on: date

                                        )

                                        ? "minus"

                                        : habit.isCompleted(

                                            on: date

                                        )

                                        ? "checkmark.circle.fill"

                                        : "circle"

                                )

                                .foregroundStyle(

                                    habit.isCompleted(

                                        on: date

                                    )

                                    ? .indigo

                                    : .secondary

                                )

                                .frame(

                                    width: 42,

                                    height: 42

                                )

                            }

                            .disabled(

                                !habit.isScheduled(

                                    on: date

                                )

                            )

                        }

                    }

                }

            }

            .padding(16)

        }

        .background(

            PremiumCardBackground()

        )

    }

    private func weekday(

        _ date: Date

    ) -> String {

        let formatter = DateFormatter()

        formatter.dateFormat = "EE"

        return formatter.string(

            from: date

        )

    }

}

struct MonthTrackerHeatmap: View {

    let tracker: Tracker

    @Binding var displayedMonth: Date

    @Binding var selectedDate: Date

    private let calendar =

        Calendar.current

    private let weekdayLetters =

        ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {

        VStack(spacing: 14) {

            HStack {

                Button {

                    moveMonth(-1)

                } label: {

                    SmallCircleButton(

                        icon:

                            "chevron.left"

                    )

                }

                Spacer()

                Text(monthTitle)

                    .font(.headline)

                Spacer()

                Button {

                    moveMonth(1)

                } label: {

                    SmallCircleButton(

                        icon:

                            "chevron.right"

                    )

                }

            }

            HStack {

                ForEach(

                    weekdayLetters.indices,

                    id: \.self

                ) { index in

                    Text(

                        weekdayLetters[index]

                    )

                    .font(.caption2)

                    .fontWeight(.bold)

                    .foregroundStyle(.secondary)

                    .frame(

                        maxWidth: .infinity

                    )

                }

            }

            let days =

                monthDays()

            LazyVGrid(

                columns:

                    Array(

                        repeating:

                            GridItem(.flexible()),

                        count: 7

                    ),

                spacing: 10

            ) {

                ForEach(

                    days.indices,

                    id: \.self

                ) { index in

                    if let date =

                        days[index] {

                        MonthRingDay(

                            date: date,

                            completion:

                                completion(

                                    date

                                ),

                            selected:

                                calendar.isDate(

                                    date,

                                    inSameDayAs:

                                        selectedDate

                                )

                        ) {

                            selectedDate =

                                date

                        }

                    } else {

                        Color.clear

                            .frame(height: 36)

                    }

                }

            }

        }

        .padding(16)

        .background(

            PremiumCardBackground()

        )

    }

    private var monthTitle: String {

        let formatter = DateFormatter()

        formatter.dateFormat =

            "MMMM yyyy"

        return formatter.string(

            from:

                displayedMonth

        )

    }

    private func moveMonth(

        _ direction: Int

    ) {

        if let date =

            calendar.date(

                byAdding: .month,

                value: direction,

                to:

                    displayedMonth

            ) {

            displayedMonth =

                date

        }

    }

    private func completion(

        _ date: Date

    ) -> Double {

        let habits =

            tracker.orderedHabits.filter {

                $0.isScheduled(

                    on: date

                )

            }

        guard !habits.isEmpty else {

            return 0

        }

        let done =

            habits.filter {

                $0.isCompleted(

                    on: date

                )

            }

            .count

        return

            Double(done)

            /

            Double(habits.count)

    }

    private func monthDays()

    -> [Date?] {

        guard

            let range =

                calendar.range(

                    of: .day,

                    in: .month,

                    for:

                        displayedMonth

                ),

            let first =

                calendar.date(

                    from:

                        calendar.dateComponents(

                            [.year, .month],

                            from:

                                displayedMonth

                        )

                )

        else {

            return []

        }

        let weekday =

            calendar.component(

                .weekday,

                from: first

            )

        var output:

            [Date?] =

            Array(

                repeating: nil,

                count:

                    weekday - 1

            )

        for day in range {

            output.append(

                calendar.date(

                    byAdding: .day,

                    value:

                        day - 1,

                    to: first

                )

            )

        }

        while output.count % 7 != 0 {

            output.append(nil)

        }

        return output

    }

}

struct MonthRingDay: View {

    let date: Date

    let completion: Double

    let selected: Bool

    let action: () -> Void

    var body: some View {

        Button(

            action: action

        ) {

            ZStack {

                Circle()

                    .stroke(

                        Color.primary.opacity(

                            0.08

                        ),

                        lineWidth: 3

                    )

                Circle()

                    .trim(

                        from: 0,

                        to:

                            min(

                                max(

                                    completion,

                                    0

                                ),

                                1

                            )

                    )

                    .stroke(

                        .indigo,

                        style:

                            StrokeStyle(

                                lineWidth: 3,

                                lineCap: .round

                            )

                    )

                    .rotationEffect(

                        .degrees(-90)

                    )

                Text(

                    "\(Calendar.current.component(.day, from: date))"

                )

                .font(.caption2)

                .fontWeight(

                    selected

                    ? .bold

                    : .semibold

                )

            }

            .frame(

                width: 34,

                height: 34

            )

            .padding(3)

            .overlay {

                if selected {

                    Circle()

                        .stroke(

                            .indigo,

                            lineWidth: 1

                        )

                        .frame(

                            width: 42,

                            height: 42

                        )

                }

            }

        }

        .buttonStyle(.plain)

    }

}

struct SelectedTrackerDayCard: View {

    let date: Date

    let completed: Int

    let total: Int

    let progress: Double

    var body: some View {

        HStack(spacing: 16) {

            ProgressRing(

                progress: progress,

                size: 60,

                lineWidth: 7

            )

            VStack(

                alignment: .leading,

                spacing: 4

            ) {

                Text(dateText)

                    .font(.headline)

                Text(

                    "\(completed) of \(total) completed"

                )

                .font(.caption)

                .foregroundStyle(.secondary)

            }

            Spacer()

        }

        .padding(16)

        .background(

            PremiumCardBackground()

        )

    }

    private var dateText: String {

        let formatter = DateFormatter()

        formatter.dateFormat =

            "EEEE, MMM d"

        return formatter.string(

            from: date

        )

    }

}

// MARK: - TRACKER/HABIT FORMS

struct CreateTrackerView: View {

    @Environment(\.modelContext)

    private var modelContext

    @Environment(\.dismiss)

    private var dismiss

    @State private var name =

        ""

    @State private var icon =

        "star.fill"

    @State private var habitName =

        ""

    @State private var habits:

        [String] = []

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(

                    alignment: .leading,

                    spacing: 22

                ) {

                    SheetHeader(

                        eyebrow:

                            "CREATE TRACKER",

                        title:

                            "Build your own",

                        subtitle:

                            "Track anything that matters to you."

                    )

                    FormLabel(text: "NAME")

                    TextField(

                        "e.g. Fitness",

                        text: $name

                    )

                    .premiumField()

                    FormLabel(text: "ICON")

                    IconPicker(

                        selectedIcon:

                            $icon

                    )

                    FormLabel(text: "HABITS")

                    HStack {

                        TextField(

                            "Add a habit",

                            text:

                                $habitName

                        )

                        Button {

                            addHabit()

                        } label: {

                            Image(

                                systemName:

                                    "plus"

                            )

                            .foregroundStyle(.white)

                            .frame(

                                width: 38,

                                height: 38

                            )

                            .background(

                                .indigo,

                                in: Circle()

                            )

                        }

                    }

                    .padding(10)

                    .background(

                        PremiumCardBackground()

                    )

                    ForEach(

                        habits,

                        id: \.self

                    ) { habit in

                        HStack {

                            Text(habit)

                            Spacer()

                            Button {

                                habits.removeAll {

                                    $0 == habit

                                }

                            } label: {

                                Image(

                                    systemName:

                                        "minus.circle.fill"

                                )

                                .foregroundStyle(.red)

                            }

                        }

                        .padding(14)

                        .background(

                            PremiumCardBackground()

                        )

                    }

                    Button {

                        create()

                    } label: {

                        PrimaryButtonLabel(

                            title:

                                "Create Tracker"

                        )

                    }

                    .disabled(

                        name

                            .trimmingCharacters(

                                in:

                                    .whitespacesAndNewlines

                            )

                            .isEmpty

                    )

                }

                .padding(20)

            }

            .background(

                Color(

                    uiColor:

                        .systemGroupedBackground

                )

            )

            .navigationTitle(

                "New Tracker"

            )

            .navigationBarTitleDisplayMode(.inline)

            .toolbar {

                ToolbarItem(

                    placement:

                        .topBarLeading

                ) {

                    Button("Cancel") {

                        dismiss()

                    }

                }

            }

        }

    }

    private func addHabit() {

        let trimmed =

            habitName

                .trimmingCharacters(

                    in:

                        .whitespacesAndNewlines

                )

        guard !trimmed.isEmpty else {

            return

        }

        habits.append(trimmed)

        habitName = ""

    }

    private func create() {

        let trimmed =

            name

                .trimmingCharacters(

                    in:

                        .whitespacesAndNewlines

                )

        guard !trimmed.isEmpty else {

            return

        }

        let newHabits =

            habits.enumerated().map {

                index,

                habitName in

                Habit(

                    name:

                        habitName,

                    icon:

                        "checkmark.circle",

                    sortOrder:

                        index

                )

            }

        modelContext.insert(

            Tracker(

                name: trimmed,

                icon: icon,

                habits:

                    newHabits

            )

        )

        try? modelContext.save()

        dismiss()

    }

}

struct AddHabitView: View {

    @Environment(\.modelContext)

    private var modelContext

    @Environment(\.dismiss)

    private var dismiss

    let tracker: Tracker

    @State private var name = ""

    @State private var icon =

        "checkmark.circle"

    @State private var schedule:

        HabitScheduleType =

        .everyDay

    @State private var selectedDays:

        Set<Int> = []

    @State private var timesPerWeek = 3

    @State private var startDate = Date()

    @State private var reminderEnabled = false

    @State private var reminderTime =
        Calendar.current.date(
            bySettingHour: 20,
            minute: 0,
            second: 0,
            of: Date()
        ) ?? Date()

    @State private var showNotificationDeniedAlert = false

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(

                    alignment: .leading,

                    spacing: 22

                ) {

                    SheetHeader(

                        eyebrow:

                            "NEW HABIT",

                        title:

                            "Add to \(tracker.name)",

                        subtitle:

                            "Choose how and when you want to track it."

                    )

                    FormLabel(text: "NAME")

                    TextField(

                        "e.g. Morning Walk",

                        text: $name

                    )

                    .premiumField()

                    FormLabel(text: "ICON")

                    IconPicker(

                        selectedIcon:

                            $icon

                    )

                    ScheduleEditor(

                        schedule:

                            $schedule,

                        selectedDays:

                            $selectedDays,

                        timesPerWeek:

                            $timesPerWeek

                    )

                    FormLabel(

                        text:

                            "START DATE"

                    )

                    DatePicker(

                        "Start Date",

                        selection:

                            $startDate,

                        displayedComponents:

                            .date

                    )

                    .padding()

                    .background(

                        PremiumCardBackground()

                    )

                    FormLabel(
                        text:
                            "REMINDER"
                    )

                    HabitReminderEditor(
                        isEnabled:
                            $reminderEnabled,
                        reminderTime:
                            $reminderTime,
                        habitName:
                            name
                    ) {
                        showNotificationDeniedAlert =
                            true
                    }

                    Button {

                        create()

                    } label: {

                        PrimaryButtonLabel(

                            title:

                                "Add Habit"

                        )

                    }

                    .disabled(!canSave)

                }

                .padding(20)

            }

            .background(

                Color(

                    uiColor:

                        .systemGroupedBackground

                )

            )

            .navigationTitle(

                "Add Habit"

            )

            .navigationBarTitleDisplayMode(.inline)

            .toolbar {

                ToolbarItem(

                    placement:

                        .topBarLeading

                ) {

                    Button("Cancel") {

                        dismiss()

                    }

                }

            }

            .alert(
                "Notifications Are Off",
                isPresented:
                    $showNotificationDeniedAlert
            ) {
                Button("Open Settings") {
                    openNotificationSettings()
                }

                Button(
                    "Not Now",
                    role: .cancel
                ) {}
            } message: {
                Text(
                    "Enable notifications in iPhone Settings so Trackly can remind you about your habits."
                )
            }

        }

    }

    private var canSave: Bool {

        let valid =

            !name

                .trimmingCharacters(

                    in:

                        .whitespacesAndNewlines

                )

                .isEmpty

        if schedule ==

            .specificDays {

            return valid &&

            !selectedDays.isEmpty

        }

        return valid

    }

    private func create() {

        let trimmed =

            name

                .trimmingCharacters(

                    in:

                        .whitespacesAndNewlines

                )

        guard !trimmed.isEmpty else {

            return

        }

        let habit =

            Habit(

                name: trimmed,

                icon: icon,

                scheduleType:

                    schedule,

                selectedWeekdays:

                    selectedDays,

                timesPerWeek:

                    timesPerWeek,

                startDate:

                    startDate,

                sortOrder:

                    tracker.habits.count,

                reminderEnabled:
                    reminderEnabled,

                reminderHour:
                    Calendar.current.component(
                        .hour,
                        from: reminderTime
                    ),

                reminderMinute:
                    Calendar.current.component(
                        .minute,
                        from: reminderTime
                    )

            )

        tracker.habits.append(

            habit

        )

        modelContext.insert(

            habit

        )

        try? modelContext.save()

        if reminderEnabled {
            let snapshot =
                HabitReminderSnapshot(
                    id: habit.id,
                    name: habit.name,
                    scheduleTypeRaw:
                        habit.scheduleTypeRaw,
                    selectedWeekdays:
                        habit.selectedWeekdays,
                    timesPerWeek:
                        habit.timesPerWeek,
                    reminderHour:
                        habit.reminderHour ?? 20,
                    reminderMinute:
                        habit.reminderMinute ?? 0
                )

            Task {
                let success =
                    await HabitNotificationScheduler
                        .reschedule(
                            for: snapshot
                        )

                await MainActor.run {
                    if success {
                        dismiss()
                    } else {
                        showNotificationDeniedAlert =
                            true
                    }
                }
            }
        } else {
            dismiss()
        }

    }

    private func openNotificationSettings() {
        guard let url = URL(
            string:
                UIApplication.openSettingsURLString
        ) else {
            return
        }

        UIApplication.shared.open(url)
    }

}

struct EditTrackerView: View {

    @Environment(\.modelContext)

    private var modelContext

    @Environment(\.dismiss)

    private var dismiss

    let tracker: Tracker

    @State private var name: String

    @State private var icon: String

    init(

        tracker: Tracker

    ) {

        self.tracker = tracker

        _name =

            State(

                initialValue:

                    tracker.name

            )

        _icon =

            State(

                initialValue:

                    tracker.icon

            )

    }

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(

                    alignment: .leading,

                    spacing: 22

                ) {

                    SheetHeader(

                        eyebrow:

                            "EDIT TRACKER",

                        title:

                            "Customize your tracker",

                        subtitle:

                            "Update its name and icon."

                    )

                    FormLabel(text: "NAME")

                    TextField(

                        "Tracker name",

                        text: $name

                    )

                    .premiumField()

                    FormLabel(text: "ICON")

                    IconPicker(

                        selectedIcon:

                            $icon

                    )

                    Button {

                        save()

                    } label: {

                        PrimaryButtonLabel(

                            title:

                                "Save Changes"

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

            .navigationTitle(

                "Edit Tracker"

            )

        }

    }

    private func save() {

        let trimmed =

            name

                .trimmingCharacters(

                    in:

                        .whitespacesAndNewlines

                )

        guard !trimmed.isEmpty else {

            return

        }

        tracker.name = trimmed

        tracker.icon = icon

        try? modelContext.save()

        dismiss()

    }

}

struct EditHabitView: View {

    @Environment(\.modelContext)

    private var modelContext

    @Environment(\.dismiss)

    private var dismiss

    let habit: Habit

    @State private var name: String

    @State private var icon: String

    @State private var schedule:

        HabitScheduleType

    @State private var selectedDays:

        Set<Int>

    @State private var timesPerWeek:

        Int

    @State private var startDate:

        Date

    @State private var reminderEnabled:

        Bool

    @State private var reminderTime:

        Date

    @State private var showNotificationDeniedAlert =

        false

    @State private var deleteAlert =

        false

    init(

        habit: Habit

    ) {

        self.habit = habit

        _name =

            State(

                initialValue:

                    habit.name

            )

        _icon =

            State(

                initialValue:

                    habit.icon

            )

        _schedule =

            State(

                initialValue:

                    habit.scheduleType

            )

        _selectedDays =

            State(

                initialValue:

                    habit.selectedWeekdays

            )

        _timesPerWeek =

            State(

                initialValue:

                    habit.timesPerWeek

            )

        _startDate =

            State(

                initialValue:

                    habit.startDate

            )

        _reminderEnabled =

            State(

                initialValue:

                    habit.reminderEnabled
                    ?? false

            )

        var reminderComponents =
            DateComponents()

        reminderComponents.hour =
            habit.reminderHour
            ?? 20

        reminderComponents.minute =
            habit.reminderMinute
            ?? 0

        _reminderTime =

            State(

                initialValue:

                    Calendar.current.date(
                        from:
                            reminderComponents
                    )
                    ?? Date()

            )

    }

    var body: some View {

        ScrollView {

            VStack(

                alignment: .leading,

                spacing: 22

            ) {

                FormLabel(text: "NAME")

                TextField(

                    "Habit name",

                    text: $name

                )

                .premiumField()

                FormLabel(text: "ICON")

                IconPicker(

                    selectedIcon:

                        $icon

                )

                ScheduleEditor(

                    schedule:

                        $schedule,

                    selectedDays:

                        $selectedDays,

                    timesPerWeek:

                        $timesPerWeek

                )

                DatePicker(

                    "Start Date",

                    selection:

                        $startDate,

                    displayedComponents:

                        .date

                )

                .padding()

                .background(

                    PremiumCardBackground()

                )

                FormLabel(
                    text:
                        "REMINDER"
                )

                HabitReminderEditor(
                    isEnabled:
                        $reminderEnabled,
                    reminderTime:
                        $reminderTime,
                    habitName:
                        name
                ) {
                    showNotificationDeniedAlert =
                        true
                }

                Button {

                    save()

                } label: {

                    PrimaryButtonLabel(

                        title:

                            "Save Changes"

                    )

                }

                Button(

                    role: .destructive

                ) {

                    deleteAlert =

                        true

                } label: {

                    Label(

                        "Delete Habit",

                        systemImage:

                            "trash"

                    )

                    .fontWeight(.semibold)

                    .frame(

                        maxWidth:

                            .infinity

                    )

                    .frame(height: 54)

                    .background(

                        Color.red.opacity(

                            0.08

                        ),

                        in:

                            RoundedRectangle(

                                cornerRadius: 18

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

        .navigationTitle(

            "Edit Habit"

        )

        .alert(

            "Delete \(habit.name)?",

            isPresented:

                $deleteAlert

        ) {

            Button(

                "Cancel",

                role: .cancel

            ) {}

            Button(

                "Delete",

                role: .destructive

            ) {

                HabitNotificationScheduler
                    .removeNotifications(
                        for: habit.id
                    )

                modelContext.delete(

                    habit

                )

                try? modelContext.save()

                dismiss()

            }

        }

        .alert(
            "Notifications Are Off",
            isPresented:
                $showNotificationDeniedAlert
        ) {
            Button("Open Settings") {
                openNotificationSettings()
            }

            Button(
                "Not Now",
                role: .cancel
            ) {}
        } message: {
            Text(
                "Your habit was saved. Enable notifications in iPhone Settings if you want Trackly to send the reminder."
            )
        }

    }

    private func save() {

        let trimmed =

            name

                .trimmingCharacters(

                    in:

                        .whitespacesAndNewlines

                )

        guard !trimmed.isEmpty else {

            return

        }

        habit.name = trimmed

        habit.icon = icon

        habit.scheduleType =

            schedule

        habit.selectedWeekdays =

            selectedDays

        habit.timesPerWeek =

            timesPerWeek

        habit.startDate =

            Calendar.current

                .startOfDay(

                    for: startDate

                )

        habit.reminderEnabled =
            reminderEnabled

        habit.reminderHour =
            Calendar.current.component(
                .hour,
                from: reminderTime
            )

        habit.reminderMinute =
            Calendar.current.component(
                .minute,
                from: reminderTime
            )

        try? modelContext.save()

        if reminderEnabled {
            let snapshot =
                HabitReminderSnapshot(
                    id: habit.id,
                    name: habit.name,
                    scheduleTypeRaw:
                        habit.scheduleTypeRaw,
                    selectedWeekdays:
                        habit.selectedWeekdays,
                    timesPerWeek:
                        habit.timesPerWeek,
                    reminderHour:
                        habit.reminderHour ?? 20,
                    reminderMinute:
                        habit.reminderMinute ?? 0
                )

            Task {
                let success =
                    await HabitNotificationScheduler
                        .reschedule(
                            for: snapshot
                        )

                await MainActor.run {
                    if success {
                        dismiss()
                    } else {
                        showNotificationDeniedAlert =
                            true
                    }
                }
            }
        } else {
            HabitNotificationScheduler
                .removeNotifications(
                    for: habit.id
                )

            dismiss()
        }

    }

    private func openNotificationSettings() {
        guard let url = URL(
            string:
                UIApplication.openSettingsURLString
        ) else {
            return
        }

        UIApplication.shared.open(url)
    }

}

struct ManageHabitsView: View {

    @Environment(\.modelContext)

    private var modelContext

    @Environment(\.dismiss)

    private var dismiss

    @Bindable var tracker: Tracker

    var body: some View {

        NavigationStack {

            List {

                ForEach(

                    tracker.orderedHabits,

                    id: \.id

                ) { habit in

                    NavigationLink {

                        EditHabitView(

                            habit:

                                habit

                        )

                    } label: {

                        VStack(

                            alignment: .leading,

                            spacing: 3

                        ) {

                            Text(

                                habit.name

                            )

                            .fontWeight(.semibold)

                            Text(

                                habit.scheduleDescription

                            )

                            .font(.caption)

                            .foregroundStyle(.secondary)

                        }

                    }

                }

                .onMove(

                    perform: move

                )

                .onDelete(

                    perform: delete

                )

            }

            .navigationTitle(

                "Manage Habits"

            )

            .toolbar {

                ToolbarItem(

                    placement:

                        .topBarLeading

                ) {

                    Button("Done") {

                        dismiss()

                    }

                }

                ToolbarItem(

                    placement:

                        .topBarTrailing

                ) {

                    EditButton()

                }

            }

        }

    }

    private func move(

        from source: IndexSet,

        to destination: Int

    ) {

        var ordered =

            tracker.orderedHabits

        ordered.move(

            fromOffsets: source,

            toOffset: destination

        )

        for (

            index,

            habit

        ) in ordered.enumerated() {

            habit.sortOrder =

                index

        }

        try? modelContext.save()

    }

    private func delete(

        at offsets: IndexSet

    ) {

        let ordered =

            tracker.orderedHabits

        for index in offsets {

            let habit =

                ordered[index]

            tracker.habits.removeAll {

                $0.id ==

                habit.id

            }

            HabitNotificationScheduler
                .removeNotifications(for: habit.id)

            modelContext.delete(

                habit

            )

        }

        try? modelContext.save()

    }

}

struct ScheduleEditor: View {

    @Binding var schedule:

        HabitScheduleType

    @Binding var selectedDays:

        Set<Int>

    @Binding var timesPerWeek:

        Int

    var body: some View {

        VStack(

            alignment: .leading,

            spacing: 12

        ) {

            FormLabel(

                text: "SCHEDULE"

            )

            Picker(

                "Schedule",

                selection:

                    $schedule

            ) {

                ForEach(

                    HabitScheduleType

                        .allCases

                ) { option in

                    Text(

                        option.rawValue

                    )

                    .tag(option)

                }

            }

            .pickerStyle(.segmented)

            if schedule ==

                .specificDays {

                WeekdaySelector(

                    selectedDays:

                        $selectedDays

                )

            }

            if schedule ==

                .timesPerWeek {

                Stepper(

                    "\(timesPerWeek) times per week",

                    value:

                        $timesPerWeek,

                    in: 1...7

                )

                .padding()

                .background(

                    PremiumCardBackground()

                )

            }

        }

    }

}

// MARK: - MONEY

struct MoneyView: View {

    @Query(

        sort: \MoneyTransaction.date,

        order: .reverse

    )

    private var transactions: [MoneyTransaction]

    @Query(

        sort: \Paycheck.payDate,

        order: .reverse

    )

    private var paychecks: [Paycheck]

    @Query

    private var savingsGoals: [SavingsGoal]

    @State private var selectedMonth = Date()

    @State private var quickExpenseCategory: ExpenseCategory = .food

    @State private var showExpense = false

    @State private var showPaycheck = false

    @State private var showOtherIncome = false

    @State private var showSavingsGoal = false

    private let calendar = Calendar.current









    // MARK: - MONTH TRANSACTIONS

    private var monthTransactions: [MoneyTransaction] {

        transactions.filter {

            calendar.isDate(

                $0.date,

                equalTo: selectedMonth,

                toGranularity: .month

            )

        }

    }









    // MARK: - MONTH PAYCHECKS

    private var monthPaychecks: [Paycheck] {

        paychecks.filter {

            calendar.isDate(

                $0.payDate,

                equalTo: selectedMonth,

                toGranularity: .month

            )

        }

    }









    // MARK: - EXPENSES

    private var expenses: Double {

        monthTransactions

            .filter {

                $0.type == .expense

            }

            .reduce(0) {

                $0 + $1.amount

            }

    }









    // MARK: - OTHER INCOME

    private var otherIncome: Double {

        monthTransactions

            .filter {

                $0.type == .otherIncome

            }

            .reduce(0) {

                $0 + $1.amount

            }

    }









    // MARK: - PAYCHECK INCOME

    private var paycheckIncome: Double {

        monthPaychecks.reduce(0) {

            $0 + $1.netPay

        }

    }









    // MARK: - TOTAL INCOME

    private var income: Double {

        paycheckIncome + otherIncome

    }









    // MARK: - SAVED

    private var saved: Double {

        income - expenses

    }









    // MARK: - SAVINGS RATE

    private var savingsRate: Double {

        guard income > 0 else {

            return 0

        }

        return saved / income

    }









    // MARK: - BODY

    var body: some View {

        NavigationStack {

            ScrollView(

                .vertical,

                showsIndicators: true

            ) {

                VStack(

                    alignment: .leading,

                    spacing: 24

                ) {

                    // MARK: Header

                    HStack {

                        VStack(

                            alignment: .leading,

                            spacing: 6

                        ) {

                            Text("MONEY")

                                .font(.caption2)

                                .fontWeight(.black)

                                .tracking(3.2)

                                .foregroundStyle(.indigo)

                            Text("Your money")

                                .font(

                                    .system(

                                        size: 31,

                                        weight: .bold,

                                        design: .rounded

                                    )

                                )

                            Text(monthTitle)

                                .font(.subheadline)

                                .foregroundStyle(.secondary)

                        }

                        Spacer()









                        // MARK: Month Menu

                        Menu {

                            Button {

                                moveMonth(-1)

                            } label: {

                                Label(

                                    "Previous Month",

                                    systemImage: "chevron.left"

                                )

                            }









                            Button {

                                selectedMonth = Date()

                            } label: {

                                Label(

                                    "This Month",

                                    systemImage: "calendar"

                                )

                            }









                            Button {

                                moveMonth(1)

                            } label: {

                                Label(

                                    "Next Month",

                                    systemImage: "chevron.right"

                                )

                            }

                        } label: {

                            Image(

                                systemName: "calendar.circle.fill"

                            )

                            .font(.title2)

                            .foregroundStyle(.indigo)

                        }

                    }









                    // MARK: Money Summary

                    MoneyHeroCard(

                        income: income,

                        spending: expenses,

                        savings: saved,

                        savingsRate: savingsRate

                    )









                    // MARK: ACCOUNTS

                    // New Accounts & Balances system

                    MoneyAccountsSection()









                    // MARK: Main Add Expense Button

                    Button {

                        quickExpenseCategory = .food

                        showExpense = true

                    } label: {

                        HStack(spacing: 14) {

                            Image(

                                systemName: "plus"

                            )

                            .font(

                                .system(

                                    size: 18,

                                    weight: .bold

                                )

                            )

                            .foregroundStyle(.indigo)

                            .frame(

                                width: 44,

                                height: 44

                            )

                            .background(

                                .white,

                                in: Circle()

                            )









                            VStack(

                                alignment: .leading,

                                spacing: 2

                            ) {

                                Text("Add Expense")

                                    .font(

                                        .system(

                                            size: 18,

                                            weight: .bold,

                                            design: .rounded

                                        )

                                    )

                                Text(

                                    "Record spending in seconds"

                                )

                                .font(.caption)

                                .opacity(0.78)

                            }









                            Spacer()









                            Image(

                                systemName: "arrow.right"

                            )

                        }

                        .foregroundStyle(.white)

                        .padding(16)

                        .background(

                            LinearGradient(

                                colors: [

                                    .indigo,

                                    .purple

                                ],

                                startPoint: .leading,

                                endPoint: .trailing

                            ),

                            in: RoundedRectangle(

                                cornerRadius: 22

                            )

                        )

                    }

                    .buttonStyle(

                        PremiumPressButtonStyle()

                    )









                    // MARK: Quick Expense

                    HomeSectionHeader(

                        title: "Quick expense",

                        subtitle: "Category → amount → save"

                    )









                    MoneyQuickCategories { category in

                        quickExpenseCategory = category

                        showExpense = true

                    }









                    // MARK: Money In

                    HomeSectionHeader(

                        title: "Money in",

                        subtitle: "Paychecks and other income"

                    )









                    HStack(spacing: 12) {

                        MoneyActionCard(

                            icon: "banknote.fill",

                            title: "Paycheck",

                            subtitle: "Paystub"

                        ) {

                            showPaycheck = true

                        }









                        MoneyActionCard(

                            icon: "plus.circle.fill",

                            title: "Income",

                            subtitle: "Other"

                        ) {

                            showOtherIncome = true

                        }

                    }









                    // MARK: Latest Paycheck

                    if let latest = paychecks.first {

                        VStack(

                            alignment: .leading,

                            spacing: 14

                        ) {

                            HStack {

                                VStack(

                                    alignment: .leading,

                                    spacing: 4

                                ) {

                                    Text("Latest paycheck")

                                        .font(.caption)

                                        .foregroundStyle(.secondary)

                                    Text(latest.employer)

                                        .font(.headline)

                                }









                                Spacer()









                                Text(

                                    latest.netPay,

                                    format: .currency(

                                        code: "CAD"

                                    )

                                )

                                .font(

                                    .system(

                                        size: 20,

                                        weight: .bold,

                                        design: .rounded

                                    )

                                )

                                .foregroundStyle(.green)

                            }









                            Divider()









                            HStack {

                                Label(

                                    latest.payDate.formatted(

                                        .dateTime

                                            .month(.abbreviated)

                                            .day()

                                    ),

                                    systemImage: "calendar"

                                )

                                Spacer()

                                Text("Net pay")

                            }

                            .font(.caption)

                            .foregroundStyle(.secondary)

                        }

                        .padding(17)

                        .background(

                            PremiumCardBackground()

                        )

                    }









                    // MARK: Spending

                    HomeSectionHeader(

                        title: "Spending",

                        subtitle:

                            "\(expenses.formatted(.currency(code: "CAD"))) this month"

                    )









                    MoneyCategoryBreakdown(

                        transactions: monthTransactions

                    )









                    // MARK: Recent Transactions

                    HomeSectionHeader(

                        title: "Recent transactions",

                        subtitle: "Latest money activity"

                    )









                    if transactions.isEmpty {

                        EmptyCard(

                            icon: "creditcard",

                            title: "No transactions yet",

                            subtitle:

                                "Record your first expense to start building your history."

                        )

                    } else {

                        VStack(spacing: 10) {

                            ForEach(

                                Array(

                                    transactions.prefix(7)

                                ),

                                id: \.id

                            ) { transaction in

                                MoneyTransactionRow(

                                    transaction: transaction

                                )

                            }

                        }

                    }









                    // MARK: Savings Goals Header

                    HStack {

                        HomeSectionHeader(

                            title: "Savings goals",

                            subtitle:

                                "\(savingsGoals.count) goals"

                        )









                        Spacer()









                        Button {

                            showSavingsGoal = true

                        } label: {

                            Image(

                                systemName: "plus"

                            )

                            .fontWeight(.bold)

                            .foregroundStyle(.indigo)

                            .frame(

                                width: 36,

                                height: 36

                            )

                            .background(

                                Color.indigo.opacity(

                                    0.09

                                ),

                                in: Circle()

                            )

                        }

                    }









                    // MARK: Savings Goals

                    if savingsGoals.isEmpty {

                        EmptyCard(

                            icon: "target",

                            title: "Create a savings goal",

                            subtitle:

                                "Save toward travel, emergencies, purchases or anything else."

                        )

                    } else {

                        ForEach(

                            savingsGoals,

                            id: \.id

                        ) { goal in

                            MoneySavingsGoalCard(

                                goal: goal

                            )

                        }

                    }

                }

                .padding(.horizontal, 20)

                .padding(.top, 20)

                .padding(.bottom, 150)

            }

            .background(

                Color(

                    uiColor:

                        .systemGroupedBackground

                )

            )

            .toolbar(

                .hidden,

                for: .navigationBar

            )









            // MARK: Quick Expense Sheet

            .sheet(

                isPresented:

                    $showExpense

            ) {

                QuickExpenseView(

                    initialCategory:

                        quickExpenseCategory

                )

                .presentationDetents(

                    [.large]

                )

            }









            // MARK: Paycheck Sheet

            .sheet(

                isPresented:

                    $showPaycheck

            ) {

                AddPaycheckView()

                    .presentationDetents(

                        [.large]

                    )

            }









            // MARK: Other Income Sheet

            .sheet(

                isPresented:

                    $showOtherIncome

            ) {

                AddOtherIncomeView()

                    .presentationDetents(

                        [.medium, .large]

                    )

            }









            // MARK: Savings Goal Sheet

            .sheet(

                isPresented:

                    $showSavingsGoal

            ) {

                AddSavingsGoalView()

                    .presentationDetents(

                        [.large]

                    )

            }

        }

    }









    // MARK: - MONTH TITLE

    private var monthTitle: String {

        let formatter = DateFormatter()

        formatter.dateFormat =

            "MMMM yyyy"

        return formatter.string(

            from: selectedMonth

        )

    }









    // MARK: - MOVE MONTH

    private func moveMonth(

        _ amount: Int

    ) {

        if let newDate =

            calendar.date(

                byAdding: .month,

                value: amount,

                to: selectedMonth

            ) {

            selectedMonth =

                newDate

        }

    }

}

// MARK: - MONEY HERO

struct MoneyHeroCard: View {

    let income: Double

    let spending: Double

    let savings: Double

    let savingsRate: Double

    var body: some View {

        VStack(

            alignment: .leading,

            spacing: 20

        ) {

            VStack(

                alignment: .leading,

                spacing: 5

            ) {

                Text(

                    "AVAILABLE THIS MONTH"

                )

                .font(.caption2)

                .fontWeight(.black)

                .tracking(1.8)

                .foregroundStyle(

                    .white.opacity(

                        0.70

                    )

                )

                Text(

                    savings,

                    format:

                        .currency(

                            code: "CAD"

                        )

                )

                .font(

                    .system(

                        size: 38,

                        weight: .bold,

                        design: .rounded

                    )

                )

                .foregroundStyle(.white)

                Label(

                    "\(Int(savingsRate * 100))% savings rate",

                    systemImage:

                        savings >= 0

                        ? "arrow.up.right"

                        : "arrow.down.right"

                )

                .font(.caption)

                .fontWeight(.semibold)

                .foregroundStyle(

                    .white.opacity(

                        0.82

                    )

                )

            }

            HStack(spacing: 8) {

                MoneyHeroStat(

                    title: "Income",

                    amount: income,

                    icon:

                        "arrow.down.circle.fill"

                )

                MoneyHeroStat(

                    title: "Spent",

                    amount:

                        spending,

                    icon:

                        "arrow.up.circle.fill"

                )

                MoneyHeroStat(

                    title: "Saved",

                    amount:

                        savings,

                    icon:

                        "banknote.fill"

                )

            }

        }

        .padding(20)

        .background(

            LinearGradient(

                colors: [

                    .indigo,

                    .purple

                ],

                startPoint:

                    .topLeading,

                endPoint:

                    .bottomTrailing

            ),

            in:

                RoundedRectangle(

                    cornerRadius: 30

                )

        )

        .shadow(

            color:

                Color.indigo.opacity(

                    0.16

                ),

            radius: 18,

            y: 9

        )

    }

}

struct MoneyHeroStat: View {

    let title: String

    let amount: Double

    let icon: String

    var body: some View {

        VStack(

            alignment: .leading,

            spacing: 5

        ) {

            Image(

                systemName:

                    icon

            )

            .font(.caption)

            .foregroundStyle(.white)

            Text(title)

                .font(.caption2)

                .foregroundStyle(

                    .white.opacity(

                        0.65

                    )

                )

            Text(

                amount,

                format:

                    .currency(

                        code: "CAD"

                    )

            )

            .font(

                .system(

                    size: 12,

                    weight: .bold,

                    design: .rounded

                )

            )

            .foregroundStyle(.white)

            .lineLimit(1)

            .minimumScaleFactor(0.6)

        }

        .padding(10)

        .frame(

            maxWidth: .infinity,

            alignment: .leading

        )

        .background(

            .white.opacity(

                0.10

            ),

            in:

                RoundedRectangle(

                    cornerRadius: 15

                )

        )

    }

}

// MARK: - QUICK EXPENSE

struct MoneyQuickCategories: View {

    let action:

        (ExpenseCategory) -> Void

    private let categories:

        [ExpenseCategory] =

        [

            .food,

            .transport,

            .shopping,

            .bills

        ]

    var body: some View {

        HStack(spacing: 9) {

            ForEach(

                categories

            ) { category in

                Button {

                    action(category)

                } label: {

                    VStack(spacing: 8) {

                        Image(

                            systemName:

                                category.icon

                        )

                        .font(.headline)

                        .foregroundStyle(.indigo)

                        Text(

                            category.rawValue

                        )

                        .font(.caption2)

                        .fontWeight(.semibold)

                        .foregroundStyle(.primary)

                        .lineLimit(1)

                        .minimumScaleFactor(0.75)

                    }

                    .frame(

                        maxWidth:

                            .infinity

                    )

                    .frame(height: 72)

                    .background(

                        PremiumCardBackground(

                            cornerRadius: 17

                        )

                    )

                }

                .buttonStyle(

                    PremiumPressButtonStyle()

                )

            }

        }

    }

}

struct QuickExpenseView: View {

        @Environment(\.modelContext)

        private var modelContext

        @Environment(\.dismiss)

        private var dismiss

        @Query(sort: \MoneyAccount.createdAt)

        private var accounts: [MoneyAccount]

        let initialCategory: ExpenseCategory

        @State private var amount = ""

        @State private var category: ExpenseCategory

        @State private var merchant = ""

        @State private var note = ""

        @State private var date = Date()

        @State private var selectedAccountID: UUID?

        init(

            initialCategory: ExpenseCategory = .food

        ) {

            self.initialCategory = initialCategory

            _category = State(

                initialValue: initialCategory

            )

        }

        private var amountValue: Double {

            Double(

                amount.replacingOccurrences(

                    of: ",",

                    with: "."

                )

            ) ?? 0

        }

        private var selectedAccount: MoneyAccount? {

            guard let selectedAccountID else {

                return nil

            }

            return accounts.first {

                $0.id == selectedAccountID

            }

        }

        private var canSave: Bool {

            amountValue > 0 &&

            selectedAccount != nil

        }

        var body: some View {

            NavigationStack {

                ScrollView {

                    VStack(

                        alignment: .leading,

                        spacing: 22

                    ) {

                        // MARK: Amount

                        VStack(

                            alignment: .leading,

                            spacing: 8

                        ) {

                            Text("AMOUNT")

                                .font(.caption2)

                                .fontWeight(.black)

                                .tracking(2)

                                .foregroundStyle(.indigo)

                            HStack(

                                alignment: .firstTextBaseline,

                                spacing: 5

                            ) {

                                Text("$")

                                    .font(

                                        .system(

                                            size: 30,

                                            weight: .bold,

                                            design: .rounded

                                        )

                                    )

                                    .foregroundStyle(.secondary)

                                TextField(

                                    "0.00",

                                    text: $amount

                                )

                                .font(

                                    .system(

                                        size: 42,

                                        weight: .bold,

                                        design: .rounded

                                    )

                                )

                                .keyboardType(.decimalPad)

                            }

                        }

                        .padding(18)

                        .background(

                            PremiumCardBackground()

                        )









                        // MARK: Account

                        VStack(

                            alignment: .leading,

                            spacing: 12

                        ) {

                            HomeSectionHeader(

                                title: "Paid from",

                                subtitle:

                                    "Choose the account used for this expense"

                            )

                            if accounts.isEmpty {

                                HStack(spacing: 12) {

                                    Image(

                                        systemName:

                                            "exclamationmark.circle.fill"

                                    )

                                    .foregroundStyle(.orange)

                                    VStack(

                                        alignment: .leading,

                                        spacing: 3

                                    ) {

                                        Text("No accounts")

                                            .fontWeight(.semibold)

                                        Text(

                                            "Create an account from the Money tab first."

                                        )

                                        .font(.caption)

                                        .foregroundStyle(.secondary)

                                    }

                                    Spacer()

                                }

                                .padding(15)

                                .background(

                                    PremiumCardBackground()

                                )

                            } else {

                                Menu {

                                    ForEach(

                                        accounts,

                                        id: \.id

                                    ) { account in

                                        Button {

                                            selectedAccountID =

                                                account.id

                                        } label: {

                                            Label(

                                                account.name,

                                                systemImage:

                                                    account.type.icon

                                            )

                                        }

                                    }

                                } label: {

                                    HStack(spacing: 14) {

                                        Image(

                                            systemName:

                                                selectedAccount?

                                                    .type.icon

                                                ?? "creditcard.fill"

                                        )

                                        .font(.title3)

                                        .foregroundStyle(.indigo)

                                        .frame(

                                            width: 44,

                                            height: 44

                                        )

                                        .background(

                                            Color.indigo.opacity(

                                                0.10

                                            ),

                                            in:

                                                RoundedRectangle(

                                                    cornerRadius: 13

                                                )

                                        )

                                        VStack(

                                            alignment: .leading,

                                            spacing: 3

                                        ) {

                                            Text(

                                                selectedAccount?

                                                    .name

                                                ?? "Select account"

                                            )

                                            .fontWeight(.semibold)

                                            .foregroundStyle(.primary)

                                            if let account =

                                                selectedAccount {

                                                Text(

                                                    account.currentBalance,

                                                    format:

                                                        .currency(

                                                            code: "CAD"

                                                        )

                                                )

                                                .font(.caption)

                                                .foregroundStyle(.secondary)

                                            } else {

                                                Text(

                                                    "Where did you pay from?"

                                                )

                                                .font(.caption)

                                                .foregroundStyle(.secondary)

                                            }

                                        }

                                        Spacer()

                                        Image(

                                            systemName:

                                                "chevron.up.chevron.down"

                                        )

                                        .font(.caption)

                                        .foregroundStyle(.secondary)

                                    }

                                    .padding(15)

                                    .background(

                                        PremiumCardBackground()

                                    )

                                }

                            }

                        }









                        // MARK: Category

                        VStack(

                            alignment: .leading,

                            spacing: 12

                        ) {

                            HomeSectionHeader(

                                title: "Category",

                                subtitle:

                                    "What was this expense for?"

                            )

                            LazyVGrid(

                                columns: [

                                    GridItem(.flexible()),

                                    GridItem(.flexible()),

                                    GridItem(.flexible())

                                ],

                                spacing: 10

                            ) {

                                ForEach(

                                    ExpenseCategory.allCases

                                ) { item in

                                    Button {

                                        category = item

                                    } label: {

                                        VStack(spacing: 8) {

                                            Image(

                                                systemName:

                                                    item.icon

                                            )

                                            .font(.title3)

                                            Text(

                                                item.rawValue

                                            )

                                            .font(.caption2)

                                            .fontWeight(.semibold)

                                            .lineLimit(1)

                                        }

                                        .foregroundStyle(

                                            category == item

                                            ? Color.white

                                            : Color.indigo

                                        )

                                        .frame(

                                            maxWidth: .infinity

                                        )

                                        .frame(height: 74)

                                        .background(

                                            category == item

                                            ? Color.indigo

                                            : Color.indigo.opacity(

                                                0.08

                                            ),

                                            in:

                                                RoundedRectangle(

                                                    cornerRadius: 16

                                                )

                                        )

                                    }

                                    .buttonStyle(.plain)

                                }

                            }

                        }









                        // MARK: Details

                        VStack(

                            alignment: .leading,

                            spacing: 12

                        ) {

                            HomeSectionHeader(

                                title: "Details",

                                subtitle: "Optional"

                            )

                            VStack(spacing: 0) {

                                HStack {

                                    Image(

                                        systemName: "storefront"

                                    )

                                    .foregroundStyle(.indigo)

                                    .frame(width: 28)

                                    TextField(

                                        "Merchant",

                                        text: $merchant

                                    )

                                }

                                .padding(15)

                                Divider()

                                    .padding(.leading, 55)

                                HStack {

                                    Image(

                                        systemName: "note.text"

                                    )

                                    .foregroundStyle(.indigo)

                                    .frame(width: 28)

                                    TextField(

                                        "Note",

                                        text: $note

                                    )

                                }

                                .padding(15)

                                Divider()

                                    .padding(.leading, 55)

                                HStack {

                                    Image(

                                        systemName: "calendar"

                                    )

                                    .foregroundStyle(.indigo)

                                    .frame(width: 28)

                                    DatePicker(

                                        "Date",

                                        selection: $date,

                                        displayedComponents:

                                            .date

                                    )

                                }

                                .padding(15)

                            }

                            .background(

                                PremiumCardBackground()

                            )

                        }









                        // MARK: Save

                        Button {

                            saveExpense()

                        } label: {

                            HStack {

                                Image(

                                    systemName:

                                        "checkmark.circle.fill"

                                )

                                Text("Add Expense")

                                    .fontWeight(.bold)

                                Spacer()

                                if amountValue > 0 {

                                    Text(

                                        amountValue,

                                        format:

                                            .currency(

                                                code: "CAD"

                                            )

                                    )

                                    .fontWeight(.bold)

                                }

                            }

                            .foregroundStyle(.white)

                            .padding(17)

                            .background(

                                LinearGradient(

                                    colors: [

                                        .indigo,

                                        .purple

                                    ],

                                    startPoint: .leading,

                                    endPoint: .trailing

                                ),

                                in:

                                    RoundedRectangle(

                                        cornerRadius: 18

                                    )

                            )

                            .opacity(

                                canSave

                                ? 1

                                : 0.45

                            )

                        }

                        .disabled(!canSave)

                        .buttonStyle(

                            PremiumPressButtonStyle()

                        )

                    }

                    .padding(20)

                }

                .background(

                    Color(

                        uiColor:

                            .systemGroupedBackground

                    )

                )

                .navigationTitle(

                    "Add Expense"

                )

                .navigationBarTitleDisplayMode(

                    .inline

                )

                .toolbar {

                    ToolbarItem(

                        placement:

                            .topBarLeading

                    ) {

                        Button("Cancel") {

                            dismiss()

                        }

                    }

                }

                .onAppear {

                    // Automatically select the first

                    // account if one exists.

                    if selectedAccountID == nil {

                        selectedAccountID =

                            accounts.first?.id

                    }

                }

            }

        }









        // MARK: - SAVE EXPENSE

        private func saveExpense() {

            guard

                amountValue > 0,

                let account = selectedAccount

            else {

                return

            }









            // 1. Create the normal transaction.

            // This powers spending analytics.

            let transaction =

                MoneyTransaction(

                    amount: amountValue,

                    date: date,

                    type: .expense,

                    category: category,

                    note:

                        note.trimmingCharacters(

                            in:

                                .whitespacesAndNewlines

                        ),

                    merchant:

                        merchant.trimmingCharacters(

                            in:

                                .whitespacesAndNewlines

                        )

                )

            modelContext.insert(

                transaction

            )









            // 2. Create the account movement.

            // This reduces the selected

            // account's balance.

            let movement =

                AccountMovement(

                    amount: amountValue,

                    date: date,

                    type: .expense,

                    note:

                        merchant.isEmpty

                        ? category.rawValue

                        : merchant,

                    linkedTransactionID:

                        transaction.id,

                    account: account

                )

            account.movements.append(

                movement

            )

            modelContext.insert(

                movement

            )









            // 3. Save everything

            try? modelContext.save()

            dismiss()

        }

    }

// MARK: - MONEY IN

struct MoneyActionCard: View {

    let icon: String

    let title: String

    let subtitle: String

    let action: () -> Void

    var body: some View {

        Button(

            action: action

        ) {

            HStack(spacing: 11) {

                Image(

                    systemName:

                        icon

                )

                .foregroundStyle(.green)

                .frame(

                    width: 38,

                    height: 38

                )

                .background(

                    Color.green.opacity(

                        0.10

                    ),

                    in:

                        RoundedRectangle(

                            cornerRadius: 12

                        )

                )

                VStack(

                    alignment: .leading,

                    spacing: 2

                ) {

                    Text(title)

                        .fontWeight(.semibold)

                    Text(subtitle)

                        .font(.caption2)

                        .foregroundStyle(.secondary)

                }

                Spacer()

            }

            .foregroundStyle(.primary)

            .padding(13)

            .frame(

                maxWidth:

                    .infinity

            )

            .background(

                PremiumCardBackground()

            )

        }

        .buttonStyle(

            PremiumPressButtonStyle()

        )

    }

}

struct AddPaycheckView: View {

    @Environment(\.modelContext)

    private var modelContext

    @Environment(\.dismiss)

    private var dismiss

    @State private var employer =

        ""

    @State private var netPay =

        ""

    @State private var payDate =

        Date()

    @State private var showDetails =

        false

    @State private var grossPay =

        ""

    @State private var deductions =

        ""

    @State private var periodStart =

        Calendar.current.date(

            byAdding: .day,

            value: -13,

            to: Date()

        )

        ?? Date()

    @State private var periodEnd =

        Date()

    @State private var note =

        ""

    @Query(sort: \MoneyAccount.createdAt)
    private var accounts: [MoneyAccount]

    @State private var depositAccountID: UUID?

    @State private var didPickDefaultAccount = false

    private var netValue: Double {

        MoneyInput.parse(netPay) ?? 0

    }

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(

                    alignment: .leading,

                    spacing: 22

                ) {

                    SheetHeader(

                        eyebrow:

                            "PAYCHECK",

                        title:

                            "Record your pay",

                        subtitle:

                            "Keep paycheck and paystub records separate from everyday income."

                    )

                    FormLabel(

                        text:

                            "NET PAY"

                    )

                    HStack {

                        Text("$")

                            .font(.title)

                            .foregroundStyle(.secondary)

                        TextField(

                            "0.00",

                            text:

                                $netPay

                        )

                        .font(

                            .system(

                                size: 34,

                                weight: .bold,

                                design: .rounded

                            )

                        )

                        .keyboardType(

                            .decimalPad

                        )

                    }

                    .padding()

                    .background(

                        PremiumCardBackground()

                    )

                    FormLabel(

                        text:

                            "EMPLOYER / SOURCE"

                    )

                    TextField(

                        "e.g. Work",

                        text:

                            $employer

                    )

                    .premiumField()

                    DatePicker(

                        "Pay Date",

                        selection:

                            $payDate,

                        displayedComponents:

                            .date

                    )

                    .padding()

                    .background(

                        PremiumCardBackground()

                    )

                    MoneyAccountPicker(
                        selectedAccountID: $depositAccountID,
                        title: "Deposit to"
                    )
                    .onAppear {
                        if !didPickDefaultAccount {
                            depositAccountID = MoneyLedger
                                .defaultDepositAccountID(in: accounts)
                            didPickDefaultAccount = true
                        }
                    }

                    Button {

                        withAnimation {

                            showDetails.toggle()

                        }

                    } label: {

                        HStack {

                            Text(

                                showDetails

                                ? "Hide paystub details"

                                : "Add paystub details"

                            )

                            Spacer()

                            Image(

                                systemName:

                                    showDetails

                                    ? "chevron.up"

                                    : "chevron.down"

                            )

                        }

                        .fontWeight(.semibold)

                        .foregroundStyle(.indigo)

                        .padding()

                        .background(

                            Color.indigo.opacity(

                                0.08

                            ),

                            in:

                                RoundedRectangle(

                                    cornerRadius: 16

                                )

                        )

                    }

                    if showDetails {

                        DatePicker(

                            "Period Start",

                            selection:

                                $periodStart,

                            displayedComponents:

                                .date

                        )

                        DatePicker(

                            "Period End",

                            selection:

                                $periodEnd,

                            displayedComponents:

                                .date

                        )

                        TextField(

                            "Gross Pay",

                            text:

                                $grossPay

                        )

                        .keyboardType(

                            .decimalPad

                        )

                        .premiumField()

                        TextField(

                            "Deductions",

                            text:

                                $deductions

                        )

                        .keyboardType(

                            .decimalPad

                        )

                        .premiumField()

                        TextField(

                            "Note",

                            text:

                                $note

                        )

                        .premiumField()

                    }

                    Button {

                        save()

                    } label: {

                        PrimaryButtonLabel(

                            title:

                                "Save Paycheck"

                        )

                    }

                    .disabled(

                        netValue <= 0

                        ||

                        employer

                            .trimmingCharacters(

                                in:

                                    .whitespacesAndNewlines

                            )

                            .isEmpty

                    )

                }

                .padding(20)

            }

            .background(

                Color(

                    uiColor:

                        .systemGroupedBackground

                )

            )

            .navigationTitle(

                "Add Paycheck"

            )

            .toolbar {

                ToolbarItem(

                    placement:

                        .topBarLeading

                ) {

                    Button("Cancel") {

                        dismiss()

                    }

                }

            }

        }

    }

    private func save() {

        let source =

            employer

                .trimmingCharacters(

                    in:

                        .whitespacesAndNewlines

                )

        guard

            netValue > 0,

            !source.isEmpty

        else {

            return

        }

        let paycheck = Paycheck(
            employer: source,
            netPay: netValue,
            grossPay: MoneyInput.parse(grossPay) ?? 0,
            deductions: MoneyInput.parse(deductions) ?? 0,
            payDate: payDate,
            periodStart: periodStart,
            periodEnd: periodEnd,
            note: note
        )

        modelContext.insert(paycheck)

        // Credit the chosen account so its balance goes up.
        MoneyLedger.depositIncome(
            amount: netValue,
            date: payDate,
            note: "Paycheck · \(source)",
            into: accounts.first { $0.id == depositAccountID },
            linkedPaycheckID: paycheck.id,
            context: modelContext
        )

        try? modelContext.save()

        dismiss()

    }

}

struct AddOtherIncomeView: View {

    @Environment(\.modelContext)

    private var modelContext

    @Environment(\.dismiss)

    private var dismiss

    @State private var amount =

        ""

    @State private var note =

        ""

    @State private var date =

        Date()

    @Query(sort: \MoneyAccount.createdAt)
    private var accounts: [MoneyAccount]

    @State private var depositAccountID: UUID?

    @State private var didPickDefaultAccount = false

    private var value: Double {

        MoneyInput.parse(amount) ?? 0

    }

    var body: some View {

        NavigationStack {

            VStack(

                alignment: .leading,

                spacing: 20

            ) {

                SheetHeader(

                    eyebrow:

                        "OTHER INCOME",

                    title:

                        "Money received",

                    subtitle:

                        "Commission, cash, refunds, freelance income, gifts and more."

                )

                HStack {

                    Text("$")

                        .font(.title)

                    TextField(

                        "0.00",

                        text:

                            $amount

                    )

                    .font(

                        .system(

                            size: 34,

                            weight: .bold,

                            design: .rounded

                        )

                    )

                    .keyboardType(

                        .decimalPad

                    )

                }

                .padding()

                .background(

                    PremiumCardBackground()

                )

                TextField(

                    "What was this for?",

                    text:

                        $note

                )

                .premiumField()

                DatePicker(

                    "Date",

                    selection:

                        $date,

                    displayedComponents:

                        .date

                )

                .padding()

                .background(

                    PremiumCardBackground()

                )

                MoneyAccountPicker(
                    selectedAccountID: $depositAccountID,
                    title: "Deposit to"
                )
                .onAppear {
                    if !didPickDefaultAccount {
                        depositAccountID = MoneyLedger
                            .defaultDepositAccountID(in: accounts)
                        didPickDefaultAccount = true
                    }
                }

                Button {

                    save()

                } label: {

                    PrimaryButtonLabel(

                        title:

                            "Add Income"

                    )

                }

                .disabled(

                    value <= 0

                )

                Spacer()

            }

            .padding(20)

            .background(

                Color(

                    uiColor:

                        .systemGroupedBackground

                )

            )

            .navigationTitle(

                "Income"

            )

            .toolbar {

                ToolbarItem(

                    placement:

                        .topBarLeading

                ) {

                    Button("Cancel") {

                        dismiss()

                    }

                }

            }

        }

    }

    private func save() {

        guard value > 0 else {

            return

        }

        let transaction = MoneyTransaction(
            amount: value,
            date: date,
            type: .otherIncome,
            category: .other,
            note: note
        )

        modelContext.insert(transaction)

        // Credit the chosen account; deleting the transaction later
        // removes this movement via MoneyLedger.deleteTransaction.
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        MoneyLedger.depositIncome(
            amount: value,
            date: date,
            note: cleanNote.isEmpty ? "Income" : cleanNote,
            into: accounts.first { $0.id == depositAccountID },
            linkedTransactionID: transaction.id,
            context: modelContext
        )

        try? modelContext.save()

        dismiss()

    }

}

// MARK: - MONEY TRANSACTIONS

struct MoneyTransactionRow: View {

    @Environment(\.modelContext)

    private var modelContext

    let transaction:

        MoneyTransaction

    private var expense: Bool {

        transaction.type ==

            .expense

    }

    var body: some View {

        HStack(spacing: 13) {

            Image(

                systemName:

                    expense

                    ? transaction.category.icon

                    : "arrow.down.circle.fill"

            )

            .font(.headline)

            .foregroundStyle(

                expense

                ? Color.indigo

                : Color.green

            )

            .frame(

                width: 44,

                height: 44

            )

            .background(

                (

                    expense

                    ? Color.indigo

                    : Color.green

                )

                .opacity(0.09),

                in:

                    RoundedRectangle(

                        cornerRadius: 13

                    )

            )

            VStack(

                alignment: .leading,

                spacing: 3

            ) {

                Text(

                    transaction.note.isEmpty

                    ? expense

                        ? transaction.category.rawValue

                        : "Other Income"

                    : transaction.note

                )

                .fontWeight(.semibold)

                Text(

                    transaction.date.formatted(

                        .dateTime

                        .month(.abbreviated)

                        .day()

                        .hour()

                        .minute()

                    )

                )

                .font(.caption)

                .foregroundStyle(.secondary)

            }

            Spacer()

            Text(

                "\(expense ? "-" : "+")\(transaction.amount.formatted(.currency(code: "CAD")))"

            )

            .fontWeight(.bold)

            .foregroundStyle(

                expense

                ? Color.primary

                : Color.green

            )

            Menu {

                Button(

                    role: .destructive

                ) {

                    // Also removes the linked account movement so
                    // the account balance is restored.
                    MoneyLedger.deleteTransaction(
                        transaction,
                        context: modelContext
                    )

                } label: {

                    Label(

                        "Delete",

                        systemImage:

                            "trash"

                    )

                }

            } label: {

                Image(

                    systemName:

                        "ellipsis"

                )

                .foregroundStyle(.secondary)

            }

        }

        .padding(14)

        .background(

            PremiumCardBackground()

        )

    }

}

struct MoneyCategoryBreakdown: View {

    let transactions:

        [MoneyTransaction]

    private var results:

        [(ExpenseCategory, Double)] {

        ExpenseCategory.allCases

            .map { category in

                let total =

                    transactions

                        .filter {

                            $0.type ==

                                .expense

                            &&

                            $0.category ==

                                category

                        }

                        .reduce(0) {

                            $0 +

                            $1.amount

                        }

                return (

                    category,

                    total

                )

            }

            .filter {

                $0.1 > 0

            }

            .sorted {

                $0.1 >

                $1.1

            }

    }

    private var total: Double {

        results.reduce(0) {

            $0 +

            $1.1

        }

    }

    var body: some View {

        if results.isEmpty {

            EmptyCard(

                icon:

                    "chart.bar",

                title:

                    "No spending yet",

                subtitle:

                    "Your category breakdown will appear here."

            )

        } else {

            VStack(spacing: 14) {

                ForEach(

                    results,

                    id:

                        \.0.rawValue

                ) { item in

                    let percentage =

                        total == 0

                        ? 0

                        : item.1 /

                        total

                    HStack(spacing: 12) {

                        Image(

                            systemName:

                                item.0.icon

                        )

                        .foregroundStyle(.indigo)

                        .frame(

                            width: 38,

                            height: 38

                        )

                        .background(

                            Color.indigo.opacity(

                                0.08

                            ),

                            in:

                                RoundedRectangle(

                                    cornerRadius: 11

                                )

                        )

                        VStack(

                            alignment: .leading,

                            spacing: 6

                        ) {

                            HStack {

                                Text(

                                    item.0.rawValue

                                )

                                .fontWeight(.semibold)

                                Spacer()

                                Text(

                                    item.1,

                                    format:

                                        .currency(

                                            code: "CAD"

                                        )

                                )

                                .font(.caption)

                                .fontWeight(.bold)

                            }

                            ProgressView(

                                value:

                                    percentage

                            )

                            .tint(.indigo)

                        }

                    }

                }

            }

            .padding(16)

            .background(

                PremiumCardBackground()

            )

        }

    }

}

// MARK: - SAVINGS

struct AddSavingsGoalView: View {

    @Environment(\.modelContext)

    private var modelContext

    @Environment(\.dismiss)

    private var dismiss

    @State private var name = ""

    @State private var target = ""

    @State private var saved = ""

    @State private var date =

        Calendar.current.date(

            byAdding: .month,

            value: 6,

            to: Date()

        )

        ?? Date()

    private var targetValue: Double {

        Double(target) ?? 0

    }

    private var savedValue: Double {

        max(Double(saved) ?? 0, 0)

    }

    private var remainingValue: Double {

        max(targetValue - savedValue, 0)

    }

    private var plannerDaysRemaining: Double {

        max(

            date.timeIntervalSince(

                Calendar.current.startOfDay(

                    for: Date()

                )

            ) / 86_400,

            0

        )

    }

    private var plannerMonthsRemaining: Double {

        plannerDaysRemaining / 30.4375

    }

    private var plannerWeeksRemaining: Double {

        plannerDaysRemaining / 7

    }

    private var plannerMonthlyAmount: Double {

        guard

            remainingValue > 0,

            plannerDaysRemaining > 0

        else {

            return 0

        }

        return remainingValue

            / max(plannerMonthsRemaining, 1)

    }

    private var plannerWeeklyAmount: Double {

        guard

            remainingValue > 0,

            plannerDaysRemaining > 0

        else {

            return 0

        }

        return remainingValue

            / max(plannerWeeksRemaining, 1)

    }

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(

                    alignment: .leading,

                    spacing: 22

                ) {

                    SheetHeader(

                        eyebrow:

                            "SAVINGS GOAL",

                        title:

                            "What are you saving for?",

                        subtitle:

                            "Give your money a purpose."

                    )

                    TextField(

                        "Goal name",

                        text: $name

                    )

                    .premiumField()

                    TextField(

                        "Target amount",

                        text:

                            $target

                    )

                    .keyboardType(

                        .decimalPad

                    )

                    .premiumField()

                    TextField(

                        "Already saved",

                        text:

                            $saved

                    )

                    .keyboardType(

                        .decimalPad

                    )

                    .premiumField()

                    DatePicker(

                        "Target Date",

                        selection:

                            $date,

                        in:

                            Calendar.current.startOfDay(

                                for: Date()

                            )...,

                        displayedComponents:

                            .date

                    )

                    .padding()

                    .background(

                        PremiumCardBackground()

                    )

                    if targetValue > 0 {

                        VStack(

                            alignment: .leading,

                            spacing: 14

                        ) {

                            HStack {

                                Image(

                                    systemName:

                                        "sparkles"

                                )

                                .foregroundStyle(

                                    .indigo

                                )

                                Text(

                                    "Your Savings Plan"

                                )

                                .font(.headline)

                                Spacer()

                            }

                            Text(

                                plannerMessage

                            )

                            .font(.subheadline)

                            .foregroundStyle(

                                .secondary

                            )

                            if remainingValue > 0 {

                                HStack(

                                    spacing: 10

                                ) {

                                    savingsPlanMetric(

                                        title:

                                            "PER MONTH",

                                        amount:

                                            plannerMonthlyAmount

                                    )

                                    savingsPlanMetric(

                                        title:

                                            "PER WEEK",

                                        amount:

                                            plannerWeeklyAmount

                                    )

                                }

                            } else {

                                Label(

                                    "You already have enough saved for this goal.",

                                    systemImage:

                                        "checkmark.circle.fill"

                                )

                                .font(.subheadline)

                                .fontWeight(

                                    .semibold

                                )

                                .foregroundStyle(

                                    .green

                                )

                            }

                        }

                        .padding(16)

                        .background(

                            PremiumCardBackground()

                        )

                    }

                    Button {

                        create()

                    } label: {

                        PrimaryButtonLabel(

                            title:

                                "Create Savings Goal"

                        )

                    }

                    .disabled(

                        targetValue <= 0

                        ||

                        name

                            .trimmingCharacters(

                                in:

                                    .whitespacesAndNewlines

                            )

                            .isEmpty

                    )

                }

                .padding(20)

            }

            .background(

                Color(

                    uiColor:

                        .systemGroupedBackground

                )

            )

            .navigationTitle(

                "Savings Goal"

            )

            .toolbar {

                ToolbarItem(

                    placement:

                        .topBarLeading

                ) {

                    Button("Cancel") {

                        dismiss()

                    }

                }

            }

        }

    }

    private var plannerMessage: String {

        if remainingValue <= 0 {

            return

                "Your goal is already fully funded."

        }

        if plannerDaysRemaining <= 0 {

            return

                "Choose a future target date to build a savings plan."

        }

        let targetText =

            date.formatted(

                .dateTime

                    .month(.wide)

                    .day()

                    .year()

            )

        return

            "To reach your goal by \(targetText), save about \(plannerMonthlyAmount.formatted(.currency(code: "CAD"))) every month."

    }

    @ViewBuilder

    private func savingsPlanMetric(

        title: String,

        amount: Double

    ) -> some View {

        VStack(

            alignment: .leading,

            spacing: 4

        ) {

            Text(title)

                .font(.caption2)

                .fontWeight(.black)

                .tracking(1)

                .foregroundStyle(

                    .secondary

                )

            Text(

                amount,

                format:

                    .currency(

                        code: "CAD"

                    )

            )

            .font(

                .system(

                    size: 18,

                    weight: .bold,

                    design: .rounded

                )

            )

            .foregroundStyle(

                .indigo

            )

        }

        .frame(

            maxWidth: .infinity,

            alignment: .leading

        )

        .padding(12)

        .background(

            Color.indigo.opacity(0.07),

            in:

                RoundedRectangle(

                    cornerRadius: 14,

                    style: .continuous

                )

        )

    }

    private func create() {

        let clean =

            name

                .trimmingCharacters(

                    in:

                        .whitespacesAndNewlines

                )

        guard

            !clean.isEmpty,

            targetValue > 0

        else {

            return

        }

        modelContext.insert(

            SavingsGoal(

                name:

                    clean,

                targetAmount:

                    targetValue,

                savedAmount:

                    Double(saved)

                    ?? 0,

                targetDate:

                    date

            )

        )

        try? modelContext.save()

        dismiss()

    }

}

struct MoneySavingsGoalCard: View {

    @Bindable var goal:

        SavingsGoal

    @Environment(\.modelContext)

    private var modelContext

    @State private var addMoney =

        false

    private var remainingAmount: Double {

        max(

            goal.targetAmount

                - goal.savedAmount,

            0

        )

    }

    private var daysRemaining: Double {

        max(

            goal.targetDate

                .timeIntervalSince(

                    Calendar.current

                        .startOfDay(

                            for: Date()

                        )

                )

                / 86_400,

            0

        )

    }

    private var monthsRemaining: Double {

        daysRemaining / 30.4375

    }

    private var weeksRemaining: Double {

        daysRemaining / 7

    }

    private var monthlyRequired: Double {

        guard

            remainingAmount > 0,

            daysRemaining > 0

        else {

            return 0

        }

        return remainingAmount

            / max(monthsRemaining, 1)

    }

    private var weeklyRequired: Double {

        guard

            remainingAmount > 0,

            daysRemaining > 0

        else {

            return 0

        }

        return remainingAmount

            / max(weeksRemaining, 1)

    }

    private var dailyRequired: Double {

        guard

            remainingAmount > 0,

            daysRemaining > 0

        else {

            return 0

        }

        return remainingAmount

            / max(daysRemaining, 1)

    }

    private var targetDatePassed: Bool {

        remainingAmount > 0

        &&

        goal.targetDate

            < Calendar.current

                .startOfDay(

                    for: Date()

                )

    }

    var body: some View {

        VStack(

            alignment: .leading,

            spacing: 13

        ) {

            HStack {

                Image(

                    systemName:

                        goal.icon

                )

                .foregroundStyle(.indigo)

                Text(

                    goal.name

                )

                .font(.headline)

                Spacer()

                Text(

                    "\(Int(goal.progress * 100))%"

                )

                .font(.caption)

                .fontWeight(.bold)

                .foregroundStyle(.indigo)

            }

            HStack {

                Text(

                    goal.savedAmount,

                    format:

                        .currency(

                            code: "CAD"

                        )

                )

                .fontWeight(.bold)

                Spacer()

                Text(

                    goal.targetAmount,

                    format:

                        .currency(

                            code: "CAD"

                        )

                )

                .font(.caption)

                .foregroundStyle(.secondary)

            }

            ProgressView(

                value:

                    goal.progress

            )

            .tint(.indigo)

            HStack {

                Text(

                    "\(remainingAmount.formatted(.currency(code: "CAD"))) remaining"

                )

                .font(.caption)

                .foregroundStyle(.secondary)

                Spacer()

                Text(

                    "Target \(goal.targetDate.formatted(.dateTime.month(.abbreviated).day().year()))"

                )

                .font(.caption)

                .foregroundStyle(

                    .secondary

                )

            }

            Divider()

                .opacity(0.6)

            VStack(

                alignment: .leading,

                spacing: 11

            ) {

                HStack {

                    Label(

                        "Savings plan",

                        systemImage:

                            "calendar.badge.clock"

                    )

                    .font(.subheadline)

                    .fontWeight(.bold)

                    .foregroundStyle(

                        .indigo

                    )

                    Spacer()

                    if remainingAmount <= 0 {

                        Text("GOAL REACHED")

                            .font(.caption2)

                            .fontWeight(.black)

                            .foregroundStyle(

                                .green

                            )

                    } else if targetDatePassed {

                        Text("DATE PASSED")

                            .font(.caption2)

                            .fontWeight(.black)

                            .foregroundStyle(

                                .red

                            )

                    }

                }

                if remainingAmount <= 0 {

                    Label(

                        "You have reached this savings goal.",

                        systemImage:

                            "checkmark.circle.fill"

                    )

                    .font(.caption)

                    .foregroundStyle(

                        .green

                    )

                } else if targetDatePassed {

                    Text(

                        "Your target date has passed. Choose a new date to create a new savings pace."

                    )

                    .font(.caption)

                    .foregroundStyle(

                        .secondary

                    )

                } else {

                    Text(

                        "Save \(monthlyRequired.formatted(.currency(code: "CAD"))) each month to reach \(goal.targetAmount.formatted(.currency(code: "CAD"))) by \(goal.targetDate.formatted(.dateTime.month(.wide).day().year()))."

                    )

                    .font(.caption)

                    .foregroundStyle(

                        .secondary

                    )

                    HStack(

                        spacing: 8

                    ) {

                        goalPlanMetric(

                            title:

                                "MONTH",

                            amount:

                                monthlyRequired

                        )

                        goalPlanMetric(

                            title:

                                "WEEK",

                            amount:

                                weeklyRequired

                        )

                        goalPlanMetric(

                            title:

                                "DAY",

                            amount:

                                dailyRequired

                        )

                    }

                }

            }

            .padding(13)

            .background(

                Color.indigo.opacity(0.06),

                in:

                    RoundedRectangle(

                        cornerRadius: 16,

                        style: .continuous

                    )

            )

            HStack {

                Spacer()

                Button(

                    "Add Money"

                ) {

                    addMoney = true

                }

                .font(.caption)

                .fontWeight(.bold)

                .foregroundStyle(.indigo)

            }

        }

        .padding(16)

        .background(

            PremiumCardBackground()

        )

        .sheet(

            isPresented:

                $addMoney

        ) {

            AddMoneyToSavingsGoalView(

                goal:

                    goal

            )

            .presentationDetents(

                [.medium]

            )

        }

    }

    @ViewBuilder

    private func goalPlanMetric(

        title: String,

        amount: Double

    ) -> some View {

        VStack(

            alignment: .leading,

            spacing: 3

        ) {

            Text(title)

                .font(.caption2)

                .fontWeight(.black)

                .foregroundStyle(

                    .secondary

                )

            Text(

                amount,

                format:

                    .currency(

                        code: "CAD"

                    )

            )

            .font(.caption)

            .fontWeight(.bold)

            .foregroundStyle(

                .primary

            )

            .lineLimit(1)

            .minimumScaleFactor(0.75)

        }

        .frame(

            maxWidth: .infinity,

            alignment: .leading

        )

        .padding(9)

        .background(

            Color(

                uiColor:

                    .secondarySystemGroupedBackground

            ),

            in:

                RoundedRectangle(

                    cornerRadius: 12,

                    style: .continuous

                )

        )

    }

}

struct AddMoneyToSavingsGoalView: View {

    @Bindable var goal:

        SavingsGoal

    @Environment(\.modelContext)

    private var modelContext

    @Environment(\.dismiss)

    private var dismiss

    @State private var amount =

        ""

    private var value: Double {

        Double(amount) ?? 0

    }

    var body: some View {

        NavigationStack {

            VStack(

                spacing: 22

            ) {

                Text(

                    goal.name

                )

                .font(

                    .system(

                        size: 25,

                        weight: .bold,

                        design: .rounded

                    )

                )

                HStack {

                    Text("$")

                        .font(.title)

                    TextField(

                        "0.00",

                        text:

                            $amount

                    )

                    .font(

                        .system(

                            size: 35,

                            weight: .bold,

                            design: .rounded

                        )

                    )

                    .keyboardType(

                        .decimalPad

                    )

                }

                .padding()

                .background(

                    PremiumCardBackground()

                )

                Button {

                    guard value > 0 else {

                        return

                    }

                    goal.savedAmount +=

                        value

                    try? modelContext.save()

                    dismiss()

                } label: {

                    PrimaryButtonLabel(

                        title:

                            "Add to Goal"

                    )

                }

                .disabled(

                    value <= 0

                )

                Spacer()

            }

            .padding(20)

            .background(

                Color(

                    uiColor:

                        .systemGroupedBackground

                )

            )

            .navigationTitle(

                "Add Savings"

            )

        }

    }

}

// MARK: - ANALYTICS HUB

struct InsightsView: View {

    @State private var analyticsType:

        AnalyticsType =

        .tracking

    var body: some View {

        VStack(spacing: 0) {

            VStack(

                alignment: .leading,

                spacing: 14

            ) {

                VStack(

                    alignment: .leading,

                    spacing: 5

                ) {

                    Text("ANALYTICS")

                        .font(.caption2)

                        .fontWeight(.black)

                        .tracking(3)

                        .foregroundStyle(.indigo)

                    Text(

                        "Your insights"

                    )

                    .font(

                        .system(

                            size: 30,

                            weight: .bold,

                            design: .rounded

                        )

                    )

                }

                Picker(

                    "Analytics",

                    selection:

                        $analyticsType

                ) {

                    Text("Tracking")

                        .tag(

                            AnalyticsType.tracking

                        )

                    Text("Money")

                        .tag(

                            AnalyticsType.money

                        )

                }

                .pickerStyle(.segmented)

            }

            .padding(.horizontal, 20)

            .padding(.top, 20)

            .padding(.bottom, 12)

            switch analyticsType {

            case .tracking:

                TrackingInsightsView()

            case .money:

                MoneyInsightsView()

            }

        }

        .background(

            Color(

                uiColor:

                    .systemGroupedBackground

            )

        )

    }

}

// MARK: - TRACKING INSIGHTS

struct TrackingInsightsView: View {

    @Query

    private var trackers:

        [Tracker]

    @State private var period:

        InsightPeriod =

        .month

    private let calendar =

        Calendar.current

    private var habits: [Habit] {

        trackers.flatMap(\.orderedHabits)

    }

    var body: some View {

        ScrollView(

            .vertical,

            showsIndicators: false

        ) {

            VStack(

                alignment: .leading,

                spacing: 22

            ) {

                Picker(

                    "Period",

                    selection:

                        $period

                ) {

                    ForEach(

                        InsightPeriod.allCases

                    ) { option in

                        Text(

                            option.rawValue

                        )

                        .tag(option)

                    }

                }

                .pickerStyle(.segmented)

                TrackingInsightHero(

                    percentage:

                        overallPercentage,

                    completed:

                        completedCount,

                    total:

                        scheduledCount

                )

                LazyVGrid(

                    columns: [

                        GridItem(.flexible()),

                        GridItem(.flexible())

                    ],

                    spacing: 12

                ) {

                    InsightStatCard(

                        icon:

                            "flame.fill",

                        title:

                            "Current Streak",

                        value:

                            "\(calculateCurrentStreak(habits: habits))",

                        subtitle:

                            "days"

                    )

                    InsightStatCard(

                        icon:

                            "checkmark.circle.fill",

                        title:

                            "Completed",

                        value:

                            "\(completedCount)",

                        subtitle:

                            period.rawValue.lowercased()

                    )

                    InsightStatCard(

                        icon:

                            "calendar.badge.checkmark",

                        title:

                            "Perfect Days",

                        value:

                            "\(perfectDays)",

                        subtitle:

                            "100% complete"

                    )

                    InsightStatCard(

                        icon:

                            "square.grid.2x2.fill",

                        title:

                            "Trackers",

                        value:

                            "\(trackers.count)",

                        subtitle:

                            "active"

                    )

                }

                HomeSectionHeader(

                    title:

                        "Habit performance",

                    subtitle:

                        "Strongest to weakest"

                )

                VStack(spacing: 14) {

                    ForEach(

                        habitPerformance

                    ) { item in

                        InsightPerformanceRow(

                            icon:

                                item.icon,

                            title:

                                item.name,

                            percentage:

                                item.percentage,

                            completions:

                                item.completed,

                            opportunities:

                                item.scheduled

                        )

                    }

                }

                .padding(16)

                .background(

                    PremiumCardBackground()

                )

                HomeSectionHeader(

                    title:

                        "Consistency by day",

                    subtitle:

                        "See which weekdays work best"

                )

                WeekdayPerformanceCard(

                    days:

                        weekdayPerformance

                )

            }

            .padding(.horizontal, 20)

            .padding(.bottom, 30)

        }

    }

    private var dates: [Date] {

        periodDates()

    }

    private var scheduledCount: Int {

        dates.reduce(0) {

            total,

            date in

            total +

            habits.filter {

                $0.isScheduled(

                    on: date

                )

            }

            .count

        }

    }

    private var completedCount: Int {

        dates.reduce(0) {

            total,

            date in

            total +

            habits.filter {

                $0.isScheduled(

                    on: date

                )

                &&

                $0.isCompleted(

                    on: date

                )

            }

            .count

        }

    }

    private var overallPercentage: Double {

        guard scheduledCount > 0 else {

            return 0

        }

        return

            Double(completedCount)

            /

            Double(scheduledCount)

    }

    private var perfectDays: Int {

        dates.filter {

            date in

            let scheduled =

                habits.filter {

                    $0.isScheduled(

                        on: date

                    )

                }

            guard !scheduled.isEmpty else {

                return false

            }

            return scheduled.allSatisfy {

                $0.isCompleted(

                    on: date

                )

            }

        }

        .count

    }

    private var habitPerformance:

        [HabitInsight] {

        habits.map {

            habit in

            let availableDates =

                dates.filter {

                    habit.isScheduled(

                        on: $0

                    )

                }

            let done =

                availableDates.filter {

                    habit.isCompleted(

                        on: $0

                    )

                }

                .count

            return HabitInsight(

                id:

                    habit.id,

                name:

                    habit.name,

                icon:

                    habit.icon,

                percentage:

                    availableDates.isEmpty

                    ? 0

                    : Double(done)

                    /

                    Double(

                        availableDates.count

                    ),

                completed:

                    done,

                scheduled:

                    availableDates.count

            )

        }

        .sorted {

            $0.percentage >

            $1.percentage

        }

    }

    private var weekdayPerformance:

        [WeekdayInsight] {

        let labels =

            [

                "Sun",

                "Mon",

                "Tue",

                "Wed",

                "Thu",

                "Fri",

                "Sat"

            ]

        return (1...7).map {

            weekday in

            let matchingDates =

                dates.filter {

                    calendar.component(

                        .weekday,

                        from: $0

                    )

                    ==

                    weekday

                }

            let scheduled =

                matchingDates.reduce(0) {

                    total,

                    date in

                    total +

                    habits.filter {

                        $0.isScheduled(

                            on: date

                        )

                    }

                    .count

                }

            let completed =

                matchingDates.reduce(0) {

                    total,

                    date in

                    total +

                    habits.filter {

                        $0.isScheduled(

                            on: date

                        )

                        &&

                        $0.isCompleted(

                            on: date

                        )

                    }

                    .count

                }

            return WeekdayInsight(

                id: weekday,

                name:

                    labels[

                        weekday - 1

                    ],

                percentage:

                    scheduled == 0

                    ? 0

                    : Double(completed)

                    /

                    Double(scheduled)

            )

        }

    }

    private func periodDates()

    -> [Date] {

        let now =

            Calendar.current.startOfDay(

                for: Date()

            )

        let start: Date

        switch period {

        case .week:

            start =

                calendar.date(

                    byAdding: .day,

                    value: -6,

                    to: now

                )

                ?? now

        case .month:

            start =

                calendar.date(

                    byAdding: .day,

                    value: -29,

                    to: now

                )

                ?? now

        case .year:

            start =

                calendar.date(

                    byAdding: .day,

                    value: -364,

                    to: now

                )

                ?? now

        }

        var result:

            [Date] = []

        var current =

            start

        while current <= now {

            result.append(

                current

            )

            guard let next =

                calendar.date(

                    byAdding: .day,

                    value: 1,

                    to: current

                )

            else {

                break

            }

            current =

                next

        }

        return result

    }

}

struct HabitInsight:

    Identifiable {

    let id: UUID

    let name: String

    let icon: String

    let percentage: Double

    let completed: Int

    let scheduled: Int

}

struct WeekdayInsight:

    Identifiable {

    let id: Int

    let name: String

    let percentage: Double

}

struct TrackingInsightHero: View {

    let percentage: Double

    let completed: Int

    let total: Int

    var body: some View {

        HStack(spacing: 18) {

            ProgressRing(

                progress:

                    percentage,

                size: 82,

                lineWidth: 9,

                lightMode: true

            )

            VStack(

                alignment: .leading,

                spacing: 6

            ) {

                Text(

                    "Overall consistency"

                )

                .font(.headline)

                .foregroundStyle(.white)

                Text(

                    "\(completed) of \(total) scheduled completions"

                )

                .font(.caption)

                .foregroundStyle(

                    .white.opacity(

                        0.72

                    )

                )

                Text(

                    "\(Int(percentage * 100))%"

                )

                .font(

                    .system(

                        size: 28,

                        weight: .bold,

                        design: .rounded

                    )

                )

                .foregroundStyle(.white)

            }

            Spacer()

        }

        .padding(20)

        .background(

            LinearGradient(

                colors: [

                    .indigo,

                    .purple

                ],

                startPoint:

                    .topLeading,

                endPoint:

                    .bottomTrailing

            ),

            in:

                RoundedRectangle(

                    cornerRadius: 28

                )

        )

    }

}

struct InsightStatCard: View {

    let icon: String

    let title: String

    let value: String

    let subtitle: String

    var body: some View {

        VStack(

            alignment: .leading,

            spacing: 10

        ) {

            Image(

                systemName:

                    icon

            )

            .foregroundStyle(.indigo)

            .frame(

                width: 36,

                height: 36

            )

            .background(

                Color.indigo.opacity(

                    0.09

                ),

                in:

                    RoundedRectangle(

                        cornerRadius: 11

                    )

            )

            Text(value)

                .font(

                    .system(

                        size: 24,

                        weight: .bold,

                        design: .rounded

                    )

                )

            Text(title)

                .font(.caption)

                .fontWeight(.semibold)

            Text(subtitle)

                .font(.caption2)

                .foregroundStyle(.secondary)

        }

        .frame(

            maxWidth: .infinity,

            alignment: .leading

        )

        .padding(16)

        .background(

            PremiumCardBackground()

        )

    }

}

struct InsightPerformanceRow: View {

    let icon: String

    let title: String

    let percentage: Double

    let completions: Int

    let opportunities: Int

    var body: some View {

        HStack(spacing: 12) {

            Image(

                systemName:

                    icon

            )

            .foregroundStyle(.indigo)

            .frame(

                width: 40,

                height: 40

            )

            .background(

                Color.indigo.opacity(

                    0.09

                ),

                in:

                    RoundedRectangle(

                        cornerRadius: 11

                    )

            )

            VStack(

                alignment: .leading,

                spacing: 7

            ) {

                HStack {

                    Text(title)

                        .fontWeight(.semibold)

                    Spacer()

                    Text(

                        "\(Int(percentage * 100))%"

                    )

                    .font(.caption)

                    .fontWeight(.bold)

                }

                ProgressView(

                    value:

                        percentage

                )

                .tint(.indigo)

                Text(

                    "\(completions) of \(opportunities) completed"

                )

                .font(.caption2)

                .foregroundStyle(.secondary)

            }

        }

    }

}

struct WeekdayPerformanceCard: View {

    let days:

        [WeekdayInsight]

    var body: some View {

        VStack(spacing: 13) {

            ForEach(

                days

            ) { day in

                HStack {

                    Text(

                        day.name

                    )

                    .font(.caption)

                    .fontWeight(.semibold)

                    .frame(

                        width: 34,

                        alignment:

                            .leading

                    )

                    ProgressView(

                        value:

                            day.percentage

                    )

                    .tint(.indigo)

                    Text(

                        "\(Int(day.percentage * 100))%"

                    )

                    .font(.caption)

                    .fontWeight(.bold)

                    .foregroundStyle(.secondary)

                    .frame(

                        width: 40,

                        alignment:

                            .trailing

                    )

                }

            }

        }

        .padding(16)

        .background(

            PremiumCardBackground()

        )

    }

}

// MARK: - MONEY INSIGHTS

struct MoneyInsightsView: View {

    @Query

    private var transactions:

        [MoneyTransaction]

    @Query

    private var paychecks:

        [Paycheck]

    private let calendar =

        Calendar.current

    private var monthTransactions:

        [MoneyTransaction] {

        transactions.filter {

            calendar.isDate(

                $0.date,

                equalTo: Date(),

                toGranularity:

                    .month

            )

        }

    }

    private var monthPaychecks:

        [Paycheck] {

        paychecks.filter {

            calendar.isDate(

                $0.payDate,

                equalTo: Date(),

                toGranularity:

                    .month

            )

        }

    }

    private var expenses: Double {

        monthTransactions

            .filter {

                $0.type ==

                    .expense

            }

            .reduce(0) {

                $0 +

                $1.amount

            }

    }

    private var otherIncome: Double {

        monthTransactions

            .filter {

                $0.type ==

                    .otherIncome

            }

            .reduce(0) {

                $0 +

                $1.amount

            }

    }

    private var paycheckIncome:

        Double {

        monthPaychecks.reduce(0) {

            $0 +

            $1.netPay

        }

    }

    private var income: Double {

        paycheckIncome +

        otherIncome

    }

    private var savings: Double {

        income -

        expenses

    }

    private var savingsRate: Double {

        guard income > 0 else {

            return 0

        }

        return savings /

        income

    }

    private var expenseCount: Int {

        monthTransactions.filter {

            $0.type ==

                .expense

        }

        .count

    }

    private var averageExpense: Double {

        guard expenseCount > 0 else {

            return 0

        }

        return expenses /

        Double(expenseCount)

    }

    var body: some View {

        ScrollView(

            .vertical,

            showsIndicators: false

        ) {

            VStack(

                alignment: .leading,

                spacing: 22

            ) {

                MoneyInsightHero(

                    income:

                        income,

                    expenses:

                        expenses,

                    savings:

                        savings,

                    savingsRate:

                        savingsRate

                )

                HomeSectionHeader(

                    title:

                        "This month",

                    subtitle:

                        "Your financial performance"

                )

                LazyVGrid(

                    columns: [

                        GridItem(.flexible()),

                        GridItem(.flexible())

                    ],

                    spacing: 12

                ) {

                    MoneyInsightStat(

                        icon:

                            "arrow.down.circle.fill",

                        title:

                            "Income",

                        value:

                            income.formatted(

                                .currency(

                                    code: "CAD"

                                )

                            )

                    )

                    MoneyInsightStat(

                        icon:

                            "arrow.up.circle.fill",

                        title:

                            "Spent",

                        value:

                            expenses.formatted(

                                .currency(

                                    code: "CAD"

                                )

                            )

                    )

                    MoneyInsightStat(

                        icon:

                            "banknote.fill",

                        title:

                            "Saved",

                        value:

                            savings.formatted(

                                .currency(

                                    code: "CAD"

                                )

                            )

                    )

                    MoneyInsightStat(

                        icon:

                            "percent",

                        title:

                            "Savings Rate",

                        value:

                            "\(Int(savingsRate * 100))%"

                    )

                    MoneyInsightStat(

                        icon:

                            "cart.fill",

                        title:

                            "Expenses",

                        value:

                            "\(expenseCount)"

                    )

                    MoneyInsightStat(

                        icon:

                            "divide",

                        title:

                            "Avg Expense",

                        value:

                            averageExpense.formatted(

                                .currency(

                                    code: "CAD"

                                )

                            )

                    )

                }

                HomeSectionHeader(

                    title:

                        "Where your money went",

                    subtitle:

                        "Spending by category"

                )

                MoneyCategoryBreakdown(

                    transactions:

                        monthTransactions

                )

                if let top =

                    topCategory {

                    SmartInsightCard(

                        icon:

                            top.0.icon,

                        title:

                            "Top Spending Category",

                        message:

                            "\(top.0.rawValue) is your biggest category this month at \(top.1.formatted(.currency(code: "CAD")))."

                    )

                }

                SmartInsightCard(

                    icon:

                        savings >= 0

                        ? "chart.line.uptrend.xyaxis"

                        : "exclamationmark.triangle.fill",

                    title:

                        savings >= 0

                        ? "Positive Cash Flow"

                        : "Spending Above Income",

                    message:

                        savings >= 0

                        ? "You have \(savings.formatted(.currency(code: "CAD"))) left after your recorded expenses."

                        : "You spent \((-savings).formatted(.currency(code: "CAD"))) more than your recorded income."

                )

                HomeSectionHeader(

                    title:

                        "Paychecks",

                    subtitle:

                        "\(monthPaychecks.count) recorded this month"

                )

                if monthPaychecks.isEmpty {

                    EmptyCard(

                        icon:

                            "banknote",

                        title:

                            "No paychecks recorded",

                        subtitle:

                            "Add paychecks in Money to build income analytics."

                    )

                } else {

                    VStack(spacing: 10) {

                        ForEach(

                            monthPaychecks,

                            id: \.id

                        ) { paycheck in

                            HStack {

                                VStack(

                                    alignment: .leading,

                                    spacing: 4

                                ) {

                                    Text(

                                        paycheck.employer

                                    )

                                    .fontWeight(.semibold)

                                    Text(

                                        paycheck.payDate.formatted(

                                            .dateTime

                                            .month(.abbreviated)

                                            .day()

                                        )

                                    )

                                    .font(.caption)

                                    .foregroundStyle(.secondary)

                                }

                                Spacer()

                                Text(

                                    paycheck.netPay,

                                    format:

                                        .currency(

                                            code: "CAD"

                                        )

                                )

                                .fontWeight(.bold)

                                .foregroundStyle(.green)

                            }

                            .padding(15)

                            .background(

                                PremiumCardBackground()

                            )

                        }

                    }

                }

            }

            .padding(.horizontal, 20)

            .padding(.bottom, 30)

        }

    }

    private var topCategory:

        (ExpenseCategory, Double)? {

        ExpenseCategory.allCases

            .map {

                category in

                let total =

                    monthTransactions

                        .filter {

                            $0.type ==

                                .expense

                            &&

                            $0.category ==

                                category

                        }

                        .reduce(0) {

                            $0 +

                            $1.amount

                        }

                return (

                    category,

                    total

                )

            }

            .filter {

                $0.1 > 0

            }

            .max {

                $0.1 <

                $1.1

            }

    }

}

struct MoneyInsightHero: View {

    let income: Double

    let expenses: Double

    let savings: Double

    let savingsRate: Double

    var body: some View {

        VStack(

            alignment: .leading,

            spacing: 10

        ) {

            Text(

                "MONTHLY SAVINGS"

            )

            .font(.caption2)

            .fontWeight(.black)

            .tracking(1.8)

            .foregroundStyle(

                .white.opacity(

                    0.70

                )

            )

            Text(

                savings,

                format:

                    .currency(

                        code: "CAD"

                    )

            )

            .font(

                .system(

                    size: 37,

                    weight: .bold,

                    design: .rounded

                )

            )

            .foregroundStyle(.white)

            ProgressView(

                value:

                    min(

                        max(

                            savingsRate,

                            0

                        ),

                        1

                    )

            )

            .tint(.white)

            Text(

                "\(Int(savingsRate * 100))% of income saved"

            )

            .font(.caption)

            .foregroundStyle(

                .white.opacity(

                    0.75

                )

            )

        }

        .padding(20)

        .frame(

            maxWidth: .infinity,

            alignment: .leading

        )

        .background(

            LinearGradient(

                colors: [

                    .indigo,

                    .purple

                ],

                startPoint:

                    .topLeading,

                endPoint:

                    .bottomTrailing

            ),

            in:

                RoundedRectangle(

                    cornerRadius: 28

                )

        )

    }

}

struct MoneyInsightStat: View {

    let icon: String

    let title: String

    let value: String

    var body: some View {

        VStack(

            alignment: .leading,

            spacing: 9

        ) {

            Image(

                systemName:

                    icon

            )

            .foregroundStyle(.indigo)

            Text(value)

                .font(

                    .system(

                        size: 19,

                        weight: .bold,

                        design: .rounded

                    )

                )

                .lineLimit(1)

                .minimumScaleFactor(0.65)

            Text(title)

                .font(.caption)

                .foregroundStyle(.secondary)

        }

        .frame(

            maxWidth: .infinity,

            alignment: .leading

        )

        .padding(16)

        .background(

            PremiumCardBackground()

        )

    }

}

struct SmartInsightCard: View {

    let icon: String

    let title: String

    let message: String

    var body: some View {

        HStack(

            alignment: .top,

            spacing: 13

        ) {

            Image(

                systemName:

                    icon

            )

            .font(

                .system(

                    size: 15,

                    weight: .bold

                )

            )

            .foregroundStyle(.indigo)

            .frame(

                width: 40,

                height: 40

            )

            .background(

                Color.indigo.opacity(

                    0.09

                ),

                in:

                    RoundedRectangle(

                        cornerRadius: 12

                    )

            )

            VStack(

                alignment: .leading,

                spacing: 4

            ) {

                Text(title)

                    .font(.headline)

                Text(message)

                    .font(.caption)

                    .foregroundStyle(.secondary)

            }

            Spacer()

        }

        .padding(15)

        .background(

            PremiumCardBackground()

        )

    }

}

// MARK: - QUICK ADD

struct QuickAddMenuView: View {

    let trackers: [Tracker]

    let selectedTab: Int

    @State private var selectedTracker:

        Tracker?

    @State private var showTracker =

        false

    @State private var showGoal =

        false

    @State private var showExpense =

        false

    @State private var showPaycheck =

        false

    @State private var showIncome =

        false

    var body: some View {

        NavigationStack {

            VStack(spacing: 12) {

                if selectedTab == 2 {

                    Button {

                        showExpense =

                            true

                    } label: {

                        AddActionRow(

                            icon:

                                "cart.fill",

                            title:

                                "Add Expense",

                            subtitle:

                                "Record spending quickly."

                        )

                    }

                    Button {

                        showPaycheck =

                            true

                    } label: {

                        AddActionRow(

                            icon:

                                "banknote.fill",

                            title:

                                "Add Paycheck",

                            subtitle:

                                "Record your paycheck or paystub."

                        )

                    }

                    Button {

                        showIncome =

                            true

                    } label: {

                        AddActionRow(

                            icon:

                                "plus.circle.fill",

                            title:

                                "Other Income",

                            subtitle:

                                "Cash, commission, refund and more."

                        )

                    }

                } else {

                    if !trackers.isEmpty {

                        Menu {

                            ForEach(

                                trackers,

                                id: \.id

                            ) { tracker in

                                Button(

                                    tracker.name

                                ) {

                                    selectedTracker =

                                        tracker

                                }

                            }

                        } label: {

                            AddActionRow(

                                icon:

                                    "checkmark.circle.fill",

                                title:

                                    "Add Habit",

                                subtitle:

                                    "Choose a tracker and add a habit."

                            )

                        }

                    }

                    Button {

                        showTracker =

                            true

                    } label: {

                        AddActionRow(

                            icon:

                                "square.grid.2x2.fill",

                            title:

                                "Create Tracker",

                            subtitle:

                                "Build a new tracking system."

                        )

                    }

                    Button {

                        showGoal =

                            true

                    } label: {

                        AddActionRow(

                            icon:

                                "target",

                            title:

                                "Add Goal",

                            subtitle:

                                "Create something to work toward."

                        )

                    }

                }

                Spacer()

            }

            .padding(20)

            .navigationTitle(

                "Quick Add"

            )

            .sheet(

                item:

                    $selectedTracker

            ) { tracker in

                AddHabitView(

                    tracker:

                        tracker

                )

            }

            .sheet(

                isPresented:

                    $showTracker

            ) {

                CreateTrackerView()

            }

            .sheet(

                isPresented:

                    $showGoal

            ) {

                AddGoalView()

            }

            .sheet(

                isPresented:

                    $showExpense

            ) {

                QuickExpenseView()

            }

            .sheet(

                isPresented:

                    $showPaycheck

            ) {

                AddPaycheckView()

            }

            .sheet(

                isPresented:

                    $showIncome

            ) {

                AddOtherIncomeView()

            }

        }

    }

}

struct AddGoalView: View {

    @Environment(\.modelContext)

    private var modelContext

    @Environment(\.dismiss)

    private var dismiss

    @State private var title =

        ""

    @State private var date =

        Calendar.current.date(

            byAdding: .month,

            value: 1,

            to: Date()

        )

        ?? Date()

    var body: some View {

        NavigationStack {

            VStack(

                alignment: .leading,

                spacing: 20

            ) {

                SheetHeader(

                    eyebrow:

                        "NEW GOAL",

                    title:

                        "Set a goal",

                    subtitle:

                        "Create something you want to achieve."

                )

                TextField(

                    "Goal name",

                    text:

                        $title

                )

                .premiumField()

                DatePicker(

                    "Target Date",

                    selection:

                        $date,

                    displayedComponents:

                        .date

                )

                .padding()

                .background(

                    PremiumCardBackground()

                )

                Button {

                    create()

                } label: {

                    PrimaryButtonLabel(

                        title:

                            "Create Goal"

                    )

                }

                .disabled(

                    title

                        .trimmingCharacters(

                            in:

                                .whitespacesAndNewlines

                        )

                        .isEmpty

                )

                Spacer()

            }

            .padding(20)

            .background(

                Color(

                    uiColor:

                        .systemGroupedBackground

                )

            )

            .navigationTitle(

                "Add Goal"

            )

        }

    }

    private func create() {

        let clean =

            title

                .trimmingCharacters(

                    in:

                        .whitespacesAndNewlines

                )

        guard !clean.isEmpty else {

            return

        }

        modelContext.insert(

            Goal(

                title: clean,

                targetDate:

                    date

            )

        )

        try? modelContext.save()

        dismiss()

    }

}


// MARK: - SETTINGS / ABOUT / PRIVACY

struct TracklySettingsView: View {

    @Environment(\.dismiss)
    private var dismiss

    @State private var notificationStatus:
        UNAuthorizationStatus = .notDetermined

    @State private var isCheckingNotifications = false

    @State private var showTestSentAlert = false

    @State private var showNotificationDeniedAlert = false

    @State private var showSupportCenter = false

    @State private var showPrivacyPolicy = false

    private var versionText: String {

        let version =
            Bundle.main.object(
                forInfoDictionaryKey:
                    "CFBundleShortVersionString"
            ) as? String
            ?? "1.0"

        let build =
            Bundle.main.object(
                forInfoDictionaryKey:
                    "CFBundleVersion"
            ) as? String
            ?? "1"

        return "\(version) (\(build))"

    }

    var body: some View {

        NavigationStack {

            ScrollView(
                .vertical,
                showsIndicators: false
            ) {

                VStack(
                    alignment: .leading,
                    spacing: 22
                ) {

                    settingsHero

                    notificationsCard

                    privacyCard

                    aboutCard

                    supportCard

                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 50)

            }
            .background(
                Color(
                    uiColor:
                        .systemGroupedBackground
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    Button("Done") {

                        dismiss()

                    }
                    .fontWeight(.semibold)

                }

            }
            .task {

                await refreshNotificationStatus()

            }
            .sheet(
                isPresented:
                    $showSupportCenter
            ) {

                TracklySupportView(
                    versionText:
                        versionText
                )

            }
            .sheet(
                isPresented:
                    $showPrivacyPolicy
            ) {

                TracklyPrivacyPolicyView()

            }
            .alert(
                "Test Notification Scheduled",
                isPresented:
                    $showTestSentAlert
            ) {

                Button("OK") {}

            } message: {

                Text(
                    "Lock your iPhone or put Trackly in the background. A test notification should arrive in about 5 seconds."
                )

            }
            .alert(
                "Notifications Are Off",
                isPresented:
                    $showNotificationDeniedAlert
            ) {

                Button("Open iPhone Settings") {

                    openAppSettings()

                }

                Button(
                    "Not Now",
                    role: .cancel
                ) {}

            } message: {

                Text(
                    "Enable Trackly notifications in iPhone Settings to receive habit and payment reminders."
                )

            }

        }

    }

    private var settingsHero: some View {

        VStack(spacing: 14) {

            ZStack {

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .indigo,
                                .purple
                            ],
                            startPoint:
                                .topLeading,
                            endPoint:
                                .bottomTrailing
                        )
                    )
                    .frame(
                        width: 82,
                        height: 82
                    )

                Image(
                    systemName:
                        "checkmark"
                )
                .font(
                    .system(
                        size: 42,
                        weight: .black,
                        design: .rounded
                    )
                )
                .foregroundStyle(.white)

            }

            VStack(spacing: 4) {

                Text("Trackly")
                    .font(
                        .system(
                            size: 28,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                Text(
                    "Track everything. Achieve more."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

            }

        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)

    }

    private var notificationsCard: some View {

        VStack(
            alignment: .leading,
            spacing: 16
        ) {

            sectionHeader(
                title: "Notifications",
                icon: "bell.badge.fill"
            )

            HStack(spacing: 12) {

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {

                    Text("Permission")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(
                        notificationStatusText
                    )
                    .font(.caption)
                    .foregroundStyle(
                        notificationStatusColor
                    )

                }

                Spacer()

                if isCheckingNotifications {

                    ProgressView()

                } else {

                    Image(
                        systemName:
                            notificationStatusIcon
                    )
                    .foregroundStyle(
                        notificationStatusColor
                    )

                }

            }

            Divider()

            infoRow(
                icon: "checkmark.square.fill",
                title: "Habit reminders",
                subtitle:
                    "Optional reminders you choose for each habit."
            )

            infoRow(
                icon: "creditcard.fill",
                title: "Payment reminders",
                subtitle:
                    "Credit-card reminders 3 days before, 1 day before, and on the due date."
            )

            if notificationStatus == .notDetermined {

                Button {

                    enableNotifications()

                } label: {

                    Label(
                        "Enable Notifications",
                        systemImage:
                            "bell.badge.fill"
                    )
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)

                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)

                Text(
                    "Tap Enable Notifications first. iPhone should show Apple's permission popup. Choose Allow."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

            } else {

                Button {

                    sendTestNotification()

                } label: {

                    Label(
                        "Send Test Notification",
                        systemImage:
                            "bell.and.waves.left.and.right.fill"
                    )
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)

                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)

            }

            Button {

                openAppSettings()

            } label: {

                Label(
                    "Open Notification Settings",
                    systemImage:
                        "gearshape.fill"
                )
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)

            }
            .buttonStyle(.bordered)

        }
        .padding(18)
        .background(
            PremiumCardBackground()
        )

    }

    private var privacyCard: some View {

        VStack(
            alignment: .leading,
            spacing: 16
        ) {

            sectionHeader(
                title: "Privacy & Data",
                icon: "hand.raised.fill"
            )

            infoRow(
                icon: "iphone",
                title: "On-device storage",
                subtitle:
                    "Your Trackly records are stored locally on this iPhone using SwiftData."
            )

            infoRow(
                icon: "lock.shield.fill",
                title: "Private by design",
                subtitle:
                    "Trackly does not need an advertising profile to manage your habits or money."
            )

            infoRow(
                icon: "icloud.slash.fill",
                title: "Cloud sync",
                subtitle:
                    "Login and cloud syncing are not enabled in this version."
            )

            Button {

                showPrivacyPolicy = true

            } label: {

                Label(
                    "Read Privacy Policy",
                    systemImage:
                        "doc.text.fill"
                )
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 48)

            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)

            Text(
                "Before App Store submission, publish this policy online and add the public URL in App Store Connect."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

        }
        .padding(18)
        .background(
            PremiumCardBackground()
        )

    }

    private var aboutCard: some View {

        VStack(
            alignment: .leading,
            spacing: 15
        ) {

            sectionHeader(
                title: "About Trackly",
                icon: "info.circle.fill"
            )

            valueRow(
                title: "Version",
                value: versionText
            )

            Divider()

            valueRow(
                title: "Platform",
                value: "iPhone"
            )

            Divider()

            valueRow(
                title: "Storage",
                value: "On Device"
            )

        }
        .padding(18)
        .background(
            PremiumCardBackground()
        )

    }

    private var supportCard: some View {

        VStack(
            alignment: .leading,
            spacing: 15
        ) {

            sectionHeader(
                title: "Support",
                icon: "questionmark.circle.fill"
            )

            Text(
                "Need help with Trackly? Open the Support Center for quick fixes, notification help, data information, and troubleshooting steps."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Button {

                showSupportCenter = true

            } label: {

                Label(
                    "Open Support Center",
                    systemImage:
                        "lifepreserver.fill"
                )
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 48)

            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)

            Text(
                "Before App Store submission, we can also connect your real support email or support website here."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

        }
        .padding(18)
        .background(
            PremiumCardBackground()
        )

    }

    private func sectionHeader(
        title: String,
        icon: String
    ) -> some View {

        HStack(spacing: 10) {

            Image(systemName: icon)
                .foregroundStyle(.indigo)
                .frame(width: 28)

            Text(title)
                .font(.headline)

        }

    }

    private func infoRow(
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {

        HStack(
            alignment: .top,
            spacing: 12
        ) {

            Image(systemName: icon)
                .foregroundStyle(.indigo)
                .frame(
                    width: 32,
                    height: 32
                )
                .background(
                    Color.indigo.opacity(0.09),
                    in: RoundedRectangle(
                        cornerRadius: 9
                    )
                )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

            }

            Spacer(minLength: 0)

        }

    }

    private func valueRow(
        title: String,
        value: String
    ) -> some View {

        HStack {

            Text(title)
                .font(.subheadline)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)

        }

    }

    private var notificationStatusText:
        String {

        switch notificationStatus {

        case .authorized:
            return "Allowed"

        case .provisional:
            return "Provisionally Allowed"

        case .ephemeral:
            return "Temporarily Allowed"

        case .denied:
            return "Off"

        case .notDetermined:
            return "Not Asked Yet"

        @unknown default:
            return "Unknown"

        }

    }

    private var notificationStatusIcon:
        String {

        switch notificationStatus {

        case .authorized,
             .provisional,
             .ephemeral:
            return "checkmark.circle.fill"

        case .denied:
            return "xmark.circle.fill"

        case .notDetermined:
            return "questionmark.circle.fill"

        @unknown default:
            return "questionmark.circle.fill"

        }

    }

    private var notificationStatusColor:
        Color {

        switch notificationStatus {

        case .authorized,
             .provisional,
             .ephemeral:
            return .green

        case .denied:
            return .red

        case .notDetermined:
            return .orange

        @unknown default:
            return .secondary

        }

    }

    @MainActor
    private func refreshNotificationStatus()
        async {

        isCheckingNotifications = true

        notificationStatus =
            await HabitNotificationScheduler
                .authorizationStatus()

        isCheckingNotifications = false

    }

    private func enableNotifications() {

        isCheckingNotifications = true

        UNUserNotificationCenter.current()
            .requestAuthorization(
                options: [
                    .alert,
                    .sound,
                    .badge
                ]
            ) { granted, _ in

                Task { @MainActor in

                    isCheckingNotifications = false

                    await refreshNotificationStatus()

                    if granted {

                        sendTestNotification()

                    } else {

                        showNotificationDeniedAlert =
                            true

                    }

                }

            }

    }

    private func sendTestNotification() {

        Task {

            let status =
                await HabitNotificationScheduler
                    .authorizationStatus()

            guard
                status == .authorized
                || status == .provisional
                || status == .ephemeral
            else {

                await MainActor.run {

                    if status == .notDetermined {

                        enableNotifications()

                    } else {

                        showNotificationDeniedAlert =
                            true

                    }

                }

                return

            }

            let content =
                UNMutableNotificationContent()

            content.title =
                "Trackly Notification Test"

            content.body =
                "Notifications are working 🎉 Your habit and payment reminders can now appear here."

            content.sound = .default

            let trigger =
                UNTimeIntervalNotificationTrigger(
                    timeInterval: 5,
                    repeats: false
                )

            let request =
                UNNotificationRequest(
                    identifier:
                        "trackly.settings.test.\(UUID().uuidString)",
                    content: content,
                    trigger: trigger
                )

            do {

                try await
                    UNUserNotificationCenter.current()
                        .add(request)

                await MainActor.run {

                    showTestSentAlert = true

                }

            } catch {

                await MainActor.run {

                    showNotificationDeniedAlert =
                        true

                }

            }

            await refreshNotificationStatus()

        }

    }

    private func openAppSettings() {

        guard let url = URL(
            string:
                UIApplication.openSettingsURLString
        ) else {
            return
        }

        UIApplication.shared.open(url)

    }

}




// MARK: - PRIVACY POLICY

struct TracklyPrivacyPolicyView: View {

    @Environment(\.dismiss)
    private var dismiss

    private let supportEmail =
        "tracklyapp.support@gmail.com"

    var body: some View {

        NavigationStack {

            ScrollView(
                .vertical,
                showsIndicators: false
            ) {

                VStack(
                    alignment: .leading,
                    spacing: 22
                ) {

                    privacyHero

                    policyCard(
                        title:
                            "1. Information You Enter",
                        icon:
                            "square.and.pencil"
                    ) {

                        policyText(
                            "Trackly lets you enter habit and tracker information, goals, savings goals, expenses, paychecks, account balances, credit-card details, budget amounts, notes, merchants, dates, and related financial or tracking information."
                        )

                    }

                    policyCard(
                        title:
                            "2. How Your Data Is Stored",
                        icon:
                            "iphone"
                    ) {

                        policyText(
                            "In this version of Trackly, your app data is stored locally on your iPhone using Apple's SwiftData framework."
                        )

                        policyText(
                            "Trackly does not currently provide account login or cloud synchronization."
                        )

                    }

                    policyCard(
                        title:
                            "3. Notifications",
                        icon:
                            "bell.badge.fill"
                    ) {

                        policyText(
                            "If you choose to enable notifications, Trackly can schedule local reminders for habits and credit-card payment due dates."
                        )

                        policyText(
                            "Notification permission is controlled by iOS. You can change or disable Trackly notifications at any time in iPhone Settings."
                        )

                    }

                    policyCard(
                        title:
                            "4. Advertising & Tracking",
                        icon:
                            "hand.raised.slash.fill"
                    ) {

                        policyText(
                            "This version of Trackly does not require an advertising profile to provide its habit-tracking and money-management features."
                        )

                        policyText(
                            "Trackly does not use its on-device records to build an advertising profile."
                        )

                    }

                    policyCard(
                        title:
                            "5. Sharing of Information",
                        icon:
                            "person.2.slash.fill"
                    ) {

                        policyText(
                            "Trackly does not intentionally sell your locally stored habit or financial records."
                        )

                        policyText(
                            "Because cloud sync is not enabled in this version, the records you enter are not uploaded by Trackly to a Trackly account service."
                        )

                    }

                    policyCard(
                        title:
                            "6. Data Deletion",
                        icon:
                            "trash.fill"
                    ) {

                        policyText(
                            "You can delete individual records inside Trackly where deletion controls are available."
                        )

                        policyText(
                            "Because this version stores data locally and does not yet use cloud sync, deleting the Trackly app from your iPhone may also remove its locally stored app data."
                        )

                    }

                    policyCard(
                        title:
                            "7. Children",
                        icon:
                            "figure.2.and.child.holdinghands"
                    ) {

                        policyText(
                            "Trackly is a general productivity and personal money-management app. It is not designed to knowingly collect personal information from children through an online Trackly account service in this version."
                        )

                    }

                    policyCard(
                        title:
                            "8. Changes to This Policy",
                        icon:
                            "arrow.triangle.2.circlepath"
                    ) {

                        policyText(
                            "This Privacy Policy may be updated when Trackly adds new features, services, cloud syncing, analytics, or other data practices."
                        )

                        policyText(
                            "The policy should be reviewed and updated before shipping any feature that changes how user data is collected, stored, shared, or processed."
                        )

                    }

                    policyCard(
                        title:
                            "9. Contact",
                        icon:
                            "envelope.fill"
                    ) {

                        policyText(
                            "For privacy questions or support, contact:"
                        )

                        Text(supportEmail)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.indigo)
                            .textSelection(.enabled)

                        Button {

                            emailPrivacySupport()

                        } label: {

                            Label(
                                "Email Privacy Support",
                                systemImage:
                                    "paperplane.fill"
                            )
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)

                        }
                        .buttonStyle(.bordered)

                    }

                    Text(
                        "Last updated: September 2, 2026"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 50)

            }
            .background(
                Color(
                    uiColor:
                        .systemGroupedBackground
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    Button("Done") {

                        dismiss()

                    }
                    .fontWeight(.semibold)

                }

            }

        }

    }

    private var privacyHero: some View {

        VStack(spacing: 12) {

            Image(
                systemName:
                    "lock.shield.fill"
            )
            .font(
                .system(
                    size: 42,
                    weight: .bold
                )
            )
            .foregroundStyle(.indigo)
            .frame(
                width: 82,
                height: 82
            )
            .background(
                Color.indigo.opacity(0.10),
                in: Circle()
            )

            Text("Trackly Privacy")
                .font(
                    .system(
                        size: 26,
                        weight: .bold,
                        design: .rounded
                    )
                )

            Text(
                "A plain-language summary of how this version of Trackly handles your information."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

    }

    private func policyCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 13
        ) {

            HStack(spacing: 10) {

                Image(systemName: icon)
                    .foregroundStyle(.indigo)
                    .frame(width: 28)

                Text(title)
                    .font(.headline)

            }

            content()

        }
        .padding(18)
        .background(
            PremiumCardBackground()
        )

    }

    private func policyText(
        _ text: String
    ) -> some View {

        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )

    }

    private func emailPrivacySupport() {

        let subject =
            "Trackly Privacy Question"

        var components =
            URLComponents()

        components.scheme = "mailto"

        components.path =
            supportEmail

        components.queryItems = [
            URLQueryItem(
                name: "subject",
                value: subject
            )
        ]

        guard
            let url = components.url
        else {
            return
        }

        UIApplication.shared.open(url)

    }

}


// MARK: - SUPPORT CENTER

struct TracklySupportView: View {

    @Environment(\.dismiss)
    private var dismiss

    @State private var copiedSupportInfo = false

    private let versionText: String

    init(versionText: String) {

        self.versionText = versionText

    }

    var body: some View {

        NavigationStack {

            ScrollView(
                .vertical,
                showsIndicators: false
            ) {

                VStack(
                    alignment: .leading,
                    spacing: 22
                ) {

                    supportHero

                    quickHelpCard

                    notificationHelpCard

                    dataHelpCard

                    troubleshootingCard

                    contactSupportCard

                    diagnosticCard

                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 50)

            }
            .background(
                Color(
                    uiColor:
                        .systemGroupedBackground
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    Button("Done") {

                        dismiss()

                    }
                    .fontWeight(.semibold)

                }

            }
            .alert(
                "Support Info Copied",
                isPresented:
                    $copiedSupportInfo
            ) {

                Button("OK") {}

            } message: {

                Text(
                    "Trackly version and device information were copied. You can paste this into an email or message when asking for help."
                )

            }

        }

    }

    private var supportHero: some View {

        VStack(spacing: 12) {

            Image(
                systemName:
                    "lifepreserver.fill"
            )
            .font(
                .system(
                    size: 42,
                    weight: .bold
                )
            )
            .foregroundStyle(.indigo)
            .frame(
                width: 82,
                height: 82
            )
            .background(
                Color.indigo.opacity(0.10),
                in: Circle()
            )

            Text("Trackly Support")
                .font(
                    .system(
                        size: 26,
                        weight: .bold,
                        design: .rounded
                    )
                )

            Text(
                "Quick answers and troubleshooting for your trackers, money tools, reminders, and app data."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

    }

    private var quickHelpCard: some View {

        supportCard(
            title: "Quick Help",
            icon: "sparkles"
        ) {

            supportItem(
                title: "How do I add a habit?",
                text:
                    "Open a tracker, tap Add Habit, choose the schedule, then save. You can also turn on a reminder before saving."
            )

            Divider()

            supportItem(
                title: "How do I add an expense?",
                text:
                    "Open Money and use the expense entry option. Choose the amount, category, merchant, date, and note."
            )

            Divider()

            supportItem(
                title: "How do savings goals work?",
                text:
                    "Set your target amount and target date. Trackly calculates the monthly, weekly, and daily pace needed to reach the goal."
            )

        }

    }

    private var notificationHelpCard: some View {

        supportCard(
            title: "Notifications",
            icon: "bell.badge.fill"
        ) {

            supportItem(
                title: "Habit reminders",
                text:
                    "Edit a habit, turn on Habit Reminder, choose a time, and save. Specific Days habits only schedule reminders on the selected days."
            )

            Divider()

            supportItem(
                title: "Payment reminders",
                text:
                    "Set a credit-card due date. Trackly schedules reminders 3 days before, 1 day before, and on the due date at 9:00 AM."
            )

            Divider()

            supportItem(
                title: "No notification appeared",
                text:
                    "Open Trackly Settings and check Notification Permission. If it says Off, open iPhone Settings and enable notifications for Trackly."
            )

        }

    }

    private var dataHelpCard: some View {

        supportCard(
            title: "Your Data",
            icon: "lock.shield.fill"
        ) {

            supportItem(
                title: "Where is my data stored?",
                text:
                    "This version stores Trackly data locally on your iPhone using SwiftData."
            )

            Divider()

            supportItem(
                title: "Will deleting the app remove data?",
                text:
                    "Because this version does not yet use cloud sync, deleting Trackly may remove locally stored app data. Keep the app installed while testing important records."
            )

            Divider()

            supportItem(
                title: "Does Trackly have cloud sync?",
                text:
                    "Not in this version. Login and cloud syncing can be added later."
            )

        }

    }

    private var troubleshootingCard: some View {

        supportCard(
            title: "Troubleshooting",
            icon: "wrench.and.screwdriver.fill"
        ) {

            numberedStep(
                number: 1,
                text:
                    "Close Trackly completely and reopen it."
            )

            numberedStep(
                number: 2,
                text:
                    "Confirm notifications are allowed in iPhone Settings if reminders are the problem."
            )

            numberedStep(
                number: 3,
                text:
                    "Check that the habit reminder time or card due date is still in the future."
            )

            numberedStep(
                number: 4,
                text:
                    "If something still fails, copy the Support Info below before reporting the issue."
            )

        }

    }

    private var contactSupportCard: some View {

        supportCard(
            title: "Contact Support",
            icon: "envelope.fill"
        ) {

            Text(
                "Still need help? Send the Trackly support team an email."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {

                Image(systemName: "envelope.fill")
                    .foregroundStyle(.indigo)

                Text(
                    "tracklyapp.support@gmail.com"
                )
                .font(.subheadline)
                .fontWeight(.semibold)
                .textSelection(.enabled)

            }

            Button {

                emailSupport()

            } label: {

                Label(
                    "Email Trackly Support",
                    systemImage:
                        "paperplane.fill"
                )
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 48)

            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)

            Text(
                "The email opens with your Trackly version and iPhone information included, which can help with troubleshooting."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

        }

    }

    private var diagnosticCard: some View {

        supportCard(
            title: "Support Info",
            icon: "doc.on.doc.fill"
        ) {

            HStack {

                Text("Trackly Version")
                    .font(.subheadline)

                Spacer()

                Text(versionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

            }

            Divider()

            HStack {

                Text("iOS Version")
                    .font(.subheadline)

                Spacer()

                Text(
                    UIDevice.current
                        .systemVersion
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

            }

            Divider()

            HStack {

                Text("Device")
                    .font(.subheadline)

                Spacer()

                Text(
                    UIDevice.current
                        .model
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

            }

            Button {

                copySupportInfo()

            } label: {

                Label(
                    "Copy Support Info",
                    systemImage:
                        "doc.on.doc.fill"
                )
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 46)

            }
            .buttonStyle(.bordered)

        }

    }

    private func supportCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 15
        ) {

            HStack(spacing: 10) {

                Image(systemName: icon)
                    .foregroundStyle(.indigo)
                    .frame(width: 28)

                Text(title)
                    .font(.headline)

            }

            content()

        }
        .padding(18)
        .background(
            PremiumCardBackground()
        )

    }

    private func supportItem(
        title: String,
        text: String
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 5
        ) {

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)

        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )

    }

    private func numberedStep(
        number: Int,
        text: String
    ) -> some View {

        HStack(
            alignment: .top,
            spacing: 12
        ) {

            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(
                    width: 26,
                    height: 26
                )
                .background(
                    Color.indigo,
                    in: Circle()
                )

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)

        }

    }

    private func emailSupport() {

        let subject =
            "Trackly Support Request"

        let body =
            """
            Hi Trackly Support,

            I need help with:

            [Please describe the issue here]


            --------------------
            Trackly Version: \(versionText)
            iOS Version: \(UIDevice.current.systemVersion)
            Device: \(UIDevice.current.model)
            --------------------
            """

        var components =
            URLComponents()

        components.scheme = "mailto"

        components.path =
            "tracklyapp.support@gmail.com"

        components.queryItems = [
            URLQueryItem(
                name: "subject",
                value: subject
            ),
            URLQueryItem(
                name: "body",
                value: body
            )
        ]

        guard
            let url = components.url
        else {
            return
        }

        UIApplication.shared.open(url)

    }

    private func copySupportInfo() {

        let text =
            """
            Trackly Version: \(versionText)
            iOS Version: \(UIDevice.current.systemVersion)
            Device: \(UIDevice.current.model)
            """

        UIPasteboard.general.string =
            text

        copiedSupportInfo = true

    }

}


// MARK: - BOTTOM BAR

struct BottomNavigationContainer: View {

    @Binding var selectedTab: Int

    @Binding var showAddMenu: Bool

    var body: some View {

        CustomTabBar(

            selectedTab:

                $selectedTab,

            showAddMenu:

                $showAddMenu

        )

        .padding(.top, 8)

        .padding(.horizontal, 12)

        .padding(.bottom, 8)

        .frame(maxWidth: .infinity)

        .background(

            Color(

                uiColor:

                    .systemGroupedBackground

            )

            .ignoresSafeArea(

                edges: .bottom

            )

        )

    }

}

struct CustomTabBar: View {

    @Binding var selectedTab: Int

    @Binding var showAddMenu: Bool

    var body: some View {

        HStack(spacing: 0) {

            TabButton(

                title: "Home",

                icon: "house.fill",

                selected:

                    selectedTab == 0

            ) {

                selectedTab = 0

            }

            TabButton(

                title: "Track",

                icon:

                    "square.grid.2x2.fill",

                selected:

                    selectedTab == 1

            ) {

                selectedTab = 1

            }

            Button {

                showAddMenu =

                    true

            } label: {

                Circle()

                    .fill(

                        LinearGradient(

                            colors: [

                                .indigo,

                                .purple

                            ],

                            startPoint:

                                .topLeading,

                            endPoint:

                                .bottomTrailing

                        )

                    )

                    .frame(

                        width: 58,

                        height: 58

                    )

                    .overlay {

                        Image(

                            systemName:

                                "plus"

                        )

                        .font(.title2)

                        .fontWeight(.bold)

                        .foregroundStyle(.white)

                    }

                    .shadow(

                        color:

                            Color.indigo.opacity(

                                0.22

                            ),

                        radius: 8,

                        y: 4

                    )

            }

            TabButton(

                title: "Money",

                icon:

                    "dollarsign.circle.fill",

                selected:

                    selectedTab == 2

            ) {

                selectedTab = 2

            }

            TabButton(

                title: "Insights",

                icon:

                    "chart.bar.fill",

                selected:

                    selectedTab == 3

            ) {

                selectedTab = 3

            }

        }

        .frame(height: 72)

        .padding(.horizontal, 8)

        .background(

            .ultraThinMaterial

        )

        .clipShape(

            RoundedRectangle(

                cornerRadius: 28

            )

        )

    }

}

struct TabButton: View {

    let title: String

    let icon: String

    let selected: Bool

    let action: () -> Void

    var body: some View {

        Button(

            action: action

        ) {

            VStack(spacing: 4) {

                Image(

                    systemName:

                        icon

                )

                .font(

                    .system(

                        size: 18,

                        weight: .semibold

                    )

                )

                Text(title)

                    .font(.caption2)

                    .fontWeight(.semibold)

            }

            .foregroundStyle(

                selected

                ? .indigo

                : .secondary

            )

            .frame(

                maxWidth: .infinity

            )

        }

    }

}

// MARK: - SHARED UI

struct HomeSectionHeader: View {

    let title: String

    let subtitle: String

    var body: some View {

        VStack(

            alignment: .leading,

            spacing: 3

        ) {

            Text(title)

                .font(

                    .system(

                        size: 21,

                        weight: .bold,

                        design: .rounded

                    )

                )

            Text(subtitle)

                .font(.caption)

                .foregroundStyle(.secondary)

        }

    }

}

struct HomeMiniStat: View {

    let icon: String

    let value: String

    let label: String

    var body: some View {

        HStack(spacing: 9) {

            Image(

                systemName:

                    icon

            )

            .font(

                .system(

                    size: 13,

                    weight: .bold

                )

            )

            .foregroundStyle(.indigo)

            .frame(

                width: 30,

                height: 30

            )

            .background(

                Color.indigo.opacity(

                    0.10

                ),

                in:

                    RoundedRectangle(

                        cornerRadius: 10

                    )

            )

            VStack(

                alignment: .leading,

                spacing: 1

            ) {

                Text(value)

                    .font(

                        .system(

                            size: 16,

                            weight: .bold,

                            design: .rounded

                        )

                    )

                Text(label)

                    .font(

                        .system(

                            size: 10,

                            weight: .semibold

                        )

                    )

                    .foregroundStyle(.secondary)

            }

            Spacer()

        }

        .padding(11)

        .frame(

            maxWidth: .infinity

        )

        .background(

            PremiumCardBackground(

                cornerRadius: 17

            )

        )

    }

}

struct PremiumProgressCard: View {

    let completed: Int

    let total: Int

    let progress: Double

    let date: Date

    let streak: Int

    var body: some View {

        HStack(spacing: 20) {

            ZStack {

                Circle()

                    .stroke(

                        .white.opacity(

                            0.20

                        ),

                        lineWidth: 9

                    )

                Circle()

                    .trim(

                        from: 0,

                        to:

                            min(

                                max(

                                    progress,

                                    0

                                ),

                                1

                            )

                    )

                    .stroke(

                        .white,

                        style:

                            StrokeStyle(

                                lineWidth: 9,

                                lineCap: .round

                            )

                    )

                    .rotationEffect(

                        .degrees(-90)

                    )

                Text(

                    "\(Int(progress * 100))%"

                )

                .font(.headline)

                .fontWeight(.black)

                .foregroundStyle(.white)

            }

            .frame(

                width: 92,

                height: 92

            )

            VStack(

                alignment: .leading,

                spacing: 8

            ) {

                Text(

                    Calendar.current.isDateInToday(

                        date

                    )

                    ? "Today's focus"

                    : date.formatted(

                        .dateTime

                        .weekday(.abbreviated)

                        .month(.abbreviated)

                        .day()

                    )

                )

                .font(.caption)

                .fontWeight(.bold)

                .foregroundStyle(

                    .white.opacity(

                        0.72

                    )

                )

                Text(

                    progress >= 1

                    ? "Day complete ✨"

                    : progress >= 0.5

                    ? "Keep the momentum"

                    : "Build your momentum"

                )

                .font(

                    .system(

                        size: 20,

                        weight: .bold,

                        design: .rounded

                    )

                )

                .foregroundStyle(.white)

                HStack {

                    Label(

                        "\(completed)/\(total)",

                        systemImage:

                            "checkmark.circle.fill"

                    )

                    Label(

                        "\(streak)d",

                        systemImage:

                            "flame.fill"

                    )

                }

                .font(.caption)

                .foregroundStyle(

                    .white.opacity(

                        0.85

                    )

                )

            }

            Spacer()

        }

        .padding(21)

        .frame(height: 154)

        .background(

            LinearGradient(

                colors: [

                    .indigo,

                    .purple

                ],

                startPoint:

                    .topLeading,

                endPoint:

                    .bottomTrailing

            ),

            in:

                RoundedRectangle(

                    cornerRadius: 30

                )

        )

    }

}

struct BriefStatCard: View {

    let icon: String

    let value: String

    let title: String

    var body: some View {

        VStack(

            alignment: .leading,

            spacing: 10

        ) {

            Image(

                systemName:

                    icon

            )

            .foregroundStyle(.indigo)

            Text(value)

                .font(

                    .system(

                        size: 24,

                        weight: .bold,

                        design: .rounded

                    )

                )

            Text(title)

                .font(.caption)

                .foregroundStyle(.secondary)

        }

        .frame(

            maxWidth: .infinity,

            alignment: .leading

        )

        .padding(16)

        .background(

            PremiumCardBackground()

        )

    }

}

struct ProgressRing: View {

    let progress: Double

    let size: CGFloat

    let lineWidth: CGFloat

    var lightMode:

        Bool = false

    var body: some View {

        ZStack {

            Circle()

                .stroke(

                    lightMode

                    ? Color.white.opacity(

                        0.2

                    )

                    : Color.indigo.opacity(

                        0.12

                    ),

                    lineWidth:

                        lineWidth

                )

            Circle()

                .trim(

                    from: 0,

                    to:

                        min(

                            max(

                                progress,

                                0

                            ),

                            1

                        )

                )

                .stroke(

                    lightMode

                    ? Color.white

                    : Color.indigo,

                    style:

                        StrokeStyle(

                            lineWidth:

                                lineWidth,

                            lineCap:

                                .round

                        )

                )

                .rotationEffect(

                    .degrees(-90)

                )

            Text(

                "\(Int(progress * 100))%"

            )

            .font(.caption)

            .fontWeight(.bold)

            .foregroundStyle(

                lightMode

                ? .white

                : .primary

            )

        }

        .frame(

            width: size,

            height: size

        )

    }

}

struct TrackerIcon: View {

    let icon: String

    let size: CGFloat

    var body: some View {

        Image(

            systemName:

                icon

        )

        .font(

            .system(

                size:

                    size * 0.34,

                weight:

                    .semibold

            )

        )

        .foregroundStyle(.white)

        .frame(

            width: size,

            height: size

        )

        .background(

            LinearGradient(

                colors: [

                    .indigo,

                    .purple

                ],

                startPoint:

                    .topLeading,

                endPoint:

                    .bottomTrailing

            ),

            in:

                RoundedRectangle(

                    cornerRadius:

                        size * 0.30

                )

        )

    }

}

struct IconPicker: View {

    @Binding var selectedIcon:

        String

    private let icons = [

        "star.fill",

        "figure.run",

        "book.fill",

        "heart.fill",

        "brain.head.profile",

        "dumbbell.fill",

        "graduationcap.fill",

        "house.fill",

        "airplane",

        "music.note",

        "gamecontroller.fill",

        "camera.fill",

        "drop.fill",

        "moon.fill",

        "fork.knife",

        "figure.walk"

    ]

    var body: some View {

        LazyVGrid(

            columns:

                Array(

                    repeating:

                        GridItem(.flexible()),

                    count: 4

                ),

            spacing: 10

        ) {

            ForEach(

                icons,

                id: \.self

            ) { icon in

                Button {

                    selectedIcon =

                        icon

                } label: {

                    Image(

                        systemName:

                            icon

                    )

                    .foregroundStyle(

                        selectedIcon ==

                            icon

                        ? .white

                        : .indigo

                    )

                    .frame(

                        maxWidth:

                            .infinity

                    )

                    .frame(height: 48)

                    .background(

                        selectedIcon ==

                            icon

                        ? Color.indigo

                        : Color.indigo.opacity(

                            0.10

                        ),

                        in:

                            RoundedRectangle(

                                cornerRadius: 14

                            )

                    )

                }

            }

        }

    }

}

struct WeekdaySelector: View {

    @Binding var selectedDays:

        Set<Int>

    var body: some View {

        HStack(spacing: 6) {

            ForEach(

                HabitWeekday.allCases

            ) { day in

                Button {

                    if selectedDays.contains(

                        day.rawValue

                    ) {

                        selectedDays.remove(

                            day.rawValue

                        )

                    } else {

                        selectedDays.insert(

                            day.rawValue

                        )

                    }

                } label: {

                    Text(

                        day.letter

                    )

                    .font(.caption)

                    .fontWeight(.bold)

                    .foregroundStyle(

                        selectedDays.contains(

                            day.rawValue

                        )

                        ? .white

                        : .indigo

                    )

                    .frame(

                        maxWidth:

                            .infinity

                    )

                    .frame(height: 38)

                    .background(

                        selectedDays.contains(

                            day.rawValue

                        )

                        ? Color.indigo

                        : Color.indigo.opacity(

                            0.10

                        ),

                        in:

                            RoundedRectangle(

                                cornerRadius: 11

                            )

                    )

                }

            }

        }

    }

}

struct FormLabel: View {

    let text: String

    var body: some View {

        Text(text)

            .font(.caption)

            .fontWeight(.bold)

            .foregroundStyle(.secondary)

    }

}

struct SheetHeader: View {

    let eyebrow: String

    let title: String

    let subtitle: String

    var body: some View {

        VStack(

            alignment: .leading,

            spacing: 6

        ) {

            Text(eyebrow)

                .font(.caption2)

                .fontWeight(.black)

                .tracking(2.5)

                .foregroundStyle(.indigo)

            Text(title)

                .font(

                    .system(

                        size: 28,

                        weight: .bold,

                        design: .rounded

                    )

                )

            Text(subtitle)

                .foregroundStyle(.secondary)

        }

    }

}

struct PrimaryButtonLabel: View {

    let title: String

    var body: some View {

        Text(title)

            .font(.headline)

            .foregroundStyle(.white)

            .frame(

                maxWidth: .infinity

            )

            .frame(height: 56)

            .background(

                LinearGradient(

                    colors: [

                        .indigo,

                        .purple

                    ],

                    startPoint:

                        .leading,

                    endPoint:

                        .trailing

                ),

                in:

                    RoundedRectangle(

                        cornerRadius: 18

                    )

            )

    }

}

struct AddActionRow: View {

    let icon: String

    let title: String

    let subtitle: String

    var body: some View {

        HStack(spacing: 15) {

            TrackerIcon(

                icon: icon,

                size: 48

            )

            VStack(

                alignment: .leading,

                spacing: 3

            ) {

                Text(title)

                    .font(.headline)

                    .foregroundStyle(.primary)

                Text(subtitle)

                    .font(.caption)

                    .foregroundStyle(.secondary)

            }

            Spacer()

            Image(

                systemName:

                    "chevron.right"

            )

            .foregroundStyle(.secondary)

        }

        .padding(14)

        .background(

            PremiumCardBackground()

        )

    }

}

struct EmptyCard: View {

    let icon: String

    let title: String

    let subtitle: String

    var body: some View {

        VStack(spacing: 10) {

            Image(

                systemName:

                    icon

            )

            .font(.title2)

            .foregroundStyle(.indigo)

            Text(title)

                .font(.headline)

            Text(subtitle)

                .font(.caption)

                .foregroundStyle(.secondary)

                .multilineTextAlignment(

                    .center

                )

        }

        .frame(

            maxWidth: .infinity

        )

        .padding(26)

        .background(

            PremiumCardBackground()

        )

    }

}

struct PremiumCardBackground: View {

    var cornerRadius:

        CGFloat = 21

    var body: some View {

        RoundedRectangle(

            cornerRadius:

                cornerRadius

        )

        .fill(

            Color(

                uiColor:

                    .secondarySystemGroupedBackground

            )

        )

    }

}

struct SmallCircleButton: View {

    let icon: String

    var body: some View {

        Image(

            systemName:

                icon

        )

        .font(

            .system(

                size: 12,

                weight: .bold

            )

        )

        .foregroundStyle(.primary)

        .frame(

            width: 32,

            height: 32

        )

        .background(

            Color.primary.opacity(

                0.05

            ),

            in: Circle()

        )

    }

}

struct PremiumPressButtonStyle:

    ButtonStyle {

    func makeBody(

        configuration:

            Configuration

    ) -> some View {

        configuration.label

            .scaleEffect(

                configuration.isPressed

                ? 0.975

                : 1

            )

            .opacity(

                configuration.isPressed

                ? 0.88

                : 1

            )

            .animation(

                .easeOut(

                    duration: 0.12

                ),

                value:

                    configuration.isPressed

            )

    }

}

extension View {

    func premiumField()

    -> some View {

        self

            .padding()

            .background(

                PremiumCardBackground()

            )

    }

}

// MARK: - STREAK

func calculateCurrentStreak(

    habits: [Habit]

) -> Int {

    guard !habits.isEmpty else {

        return 0

    }

    let calendar =

        Calendar.current

    var date =

        calendar.startOfDay(

            for: Date()

        )

    let today =

        habits.filter {

            $0.isScheduled(

                on: date

            )

        }

    if !today.isEmpty &&

        !today.allSatisfy({

            $0.isCompleted(

                on: date

            )

        }) {

        if let yesterday =

            calendar.date(

                byAdding: .day,

                value: -1,

                to: date

            ) {

            date =

                yesterday

        }

    }

    var streak = 0

    for _ in 0..<3650 {

        let scheduled =

            habits.filter {

                $0.isScheduled(

                    on: date

                )

            }

        if scheduled.isEmpty {

            guard

                let previous =

                    calendar.date(

                        byAdding: .day,

                        value: -1,

                        to: date

                    )

            else {

                break

            }

            date =

                previous

            continue

        }

        guard scheduled.allSatisfy({

            $0.isCompleted(

                on: date

            )

        }) else {

            break

        }

        streak += 1

        guard

            let previous =

                calendar.date(

                    byAdding: .day,

                    value: -1,

                    to: date

                )

        else {

            break

        }

        date =

            previous

    }

    return streak

}

// MARK: - PREVIEW

#Preview {

    ContentView()

        .modelContainer(

            for: [

                Tracker.self,

                Habit.self,

                HabitCompletion.self,

                Goal.self,

                MoneyTransaction.self,

                Paycheck.self,

                SavingsGoal.self,

                MoneyAccount.self,

                AccountMovement.self

            ],

            inMemory: true

        )

}

