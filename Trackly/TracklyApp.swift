import SwiftUI
import SwiftData
import UserNotifications
import UIKit

@main
struct TracklyApp: App {
    @UIApplicationDelegateAdaptor(TracklyAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        WindowGroup {
            TracklyLaunchView()
        }
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
                AccountMovement.self,
                MonthlyBudget.self
            ]
        )
    }
}


// MARK: - NOTIFICATION APP DELEGATE

final class TracklyAppDelegate:
    NSObject,
    UIApplicationDelegate,
    UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        UNUserNotificationCenter.current().delegate = self

        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {

        [.banner, .list, .sound, .badge]
    }

    func applicationDidBecomeActive(
        _ application: UIApplication
    ) {

        UNUserNotificationCenter.current()
            .setBadgeCount(0)

    }
}


// MARK: - SMOOTH TRACKLY OPENING

struct TracklyLaunchView: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var launchFinished = false

    @State private var ringProgress: CGFloat = 0.06
    @State private var checkScale: CGFloat = 0.82
    @State private var checkOpacity = 0.0
    @State private var textOpacity = 0.0
    @State private var textOffset: CGFloat = 6

    var body: some View {
        Group {
            if launchFinished {
                ContentView()
                    .transition(
                        .opacity.animation(
                            .easeOut(duration: 0.20)
                        )
                    )
            } else {
                TracklySmoothSplashView(
                    ringProgress: ringProgress,
                    checkScale: checkScale,
                    checkOpacity: checkOpacity,
                    textOpacity: textOpacity,
                    textOffset: textOffset
                )
                .transition(.opacity)
            }
        }
        .task {
            await runLaunchSequence()
        }
    }

    @MainActor
    private func runLaunchSequence() async {

        guard !launchFinished else {
            return
        }

        if reduceMotion {

            ringProgress = 0.93
            checkScale = 1
            checkOpacity = 1
            textOpacity = 1
            textOffset = 0

            try? await Task.sleep(
                for: .milliseconds(450)
            )

            launchFinished = true
            return
        }

        withAnimation(
            .easeOut(duration: 0.48)
        ) {
            ringProgress = 0.93
        }

        try? await Task.sleep(
            for: .milliseconds(280)
        )

        withAnimation(
            .spring(
                response: 0.28,
                dampingFraction: 0.82
            )
        ) {
            checkScale = 1
            checkOpacity = 1
        }

        try? await Task.sleep(
            for: .milliseconds(180)
        )

        withAnimation(
            .easeOut(duration: 0.22)
        ) {
            textOpacity = 1
            textOffset = 0
        }

        try? await Task.sleep(
            for: .milliseconds(360)
        )

        withAnimation(
            .easeOut(duration: 0.18)
        ) {
            launchFinished = true
        }
    }
}


// MARK: - SPLASH VIEW

struct TracklySmoothSplashView: View {
    let ringProgress: CGFloat
    let checkScale: CGFloat
    let checkOpacity: Double
    let textOpacity: Double
    let textOffset: CGFloat

    var body: some View {
        ZStack {

            LinearGradient(
                colors: [
                    Color(
                        red: 0.025,
                        green: 0.030,
                        blue: 0.120
                    ),
                    Color(
                        red: 0.030,
                        green: 0.050,
                        blue: 0.190
                    )
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {

                TracklySmoothLogo(
                    progress: ringProgress,
                    checkScale: checkScale,
                    checkOpacity: checkOpacity
                )
                .frame(
                    width: 172,
                    height: 172
                )

                VStack(spacing: 7) {

                    Text("TRACKLY")
                        .font(
                            .system(
                                size: 28,
                                weight: .black,
                                design: .rounded
                            )
                        )
                        .tracking(5)
                        .foregroundStyle(.white)

                    Text(
                        "Track everything. Achieve more."
                    )
                    .font(
                        .system(
                            size: 13,
                            weight: .medium,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(
                        .white.opacity(0.64)
                    )

                }
                .opacity(textOpacity)
                .offset(y: textOffset)

            }
            .padding(.bottom, 10)

        }
    }
}


// MARK: - SMOOTH LOGO

struct TracklySmoothLogo: View {
    let progress: CGFloat
    let checkScale: CGFloat
    let checkOpacity: Double

    var body: some View {
        ZStack {

            Circle()
                .stroke(
                    Color.white.opacity(0.055),
                    lineWidth: 18
                )
                .padding(12)

            Circle()
                .trim(
                    from: 0.06,
                    to: max(
                        0.06,
                        min(progress, 0.93)
                    )
                )
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(
                                red: 0.88,
                                green: 0.16,
                                blue: 0.96
                            ),
                            Color(
                                red: 0.46,
                                green: 0.24,
                                blue: 1.00
                            ),
                            Color(
                                red: 0.08,
                                green: 0.55,
                                blue: 1.00
                            ),
                            Color(
                                red: 0.02,
                                green: 0.88,
                                blue: 0.94
                            ),
                            Color(
                                red: 0.88,
                                green: 0.16,
                                blue: 0.96
                            )
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(
                        lineWidth: 18,
                        lineCap: .round
                    )
                )
                .rotationEffect(
                    .degrees(-70)
                )
                .padding(12)

            Image(
                systemName: "checkmark"
            )
            .font(
                .system(
                    size: 70,
                    weight: .black,
                    design: .rounded
                )
            )
            .foregroundStyle(.white)
            .scaleEffect(checkScale)
            .opacity(checkOpacity)

        }
        .drawingGroup()
    }
}


#Preview {
    TracklyLaunchView()
}

