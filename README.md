# Trackly

Trackly is an iPhone app for tracking your habits, goals, and money in one place.

## Features

- **Habits and trackers:** daily, weekday, or times-per-week habits with streaks and reminders.
- **Goals:** set goals and follow your progress.
- **Money:** expenses, paychecks and other income, monthly budgets, and savings goals.
- **Accounts:** checking, savings, cash, and credit cards, including transfers, card payments, and due-date reminders.
- **Insights:** charts and summaries for your habits and spending.
- **Private by design:** all data stays on your device. There are no accounts, no tracking, and no servers.

## Requirements

- iPhone running iOS 17.0 or later
- To build it yourself: a Mac with Xcode 26 or later

## Install

Trackly isn't on the App Store or TestFlight yet. Until it is, you can build it yourself:

1. Clone this repository:
   ```bash
   git clone https://github.com/ypatel0507/Trackly.git
   ```
2. Open `Trackly.xcodeproj` in Xcode.
3. Select the **Trackly** target, open **Signing & Capabilities**, and choose your own Apple ID team. If Xcode asks for a unique bundle identifier, change it.
4. Plug in your iPhone, select it as the run destination, and press **Run** (⌘R).
5. On your iPhone, open **Settings → General → VPN & Device Management**, then trust your developer profile.

If you build with a free Apple ID, the app stops opening after 7 days. Build and run it again to reinstall it.

## Built with

SwiftUI, SwiftData, and UserNotifications. The app has no third-party dependencies.
