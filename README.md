# Budget Planner for iPhone

A personal budget planner built natively with **Swift and SwiftUI** for iOS 17+. It's designed for Australians: amounts are in AUD, dates are dd/mm/yyyy, weeks start on Monday, and the categories match everyday Australian costs (rent, Opal/Myki, NBN, Centrelink and so on).

The app is built to answer five questions at any time:

| Question | Where it's answered |
| --- | --- |
| How much money do I have available? | **Home** – "Available now", plus "Safe to spend until payday" and a daily allowance |
| Where is my money going? | **Home** "This month" card and **Insights → Spending** (donut chart, daily chart, category drill-down) |
| What bills and expenses are coming next? | **Home** "Coming up" card, **Plan → Bills**, **Plan → Payday**, reminders and the widget |
| How much can I realistically save? | **Home** "Savings" card, **Plan → Goals** and **Insights → What if** |
| Am I staying within my budget? | **Home** "Budget" card and **Plan → Budgets** |

## Features

- **Income and expenses** – add one in three taps (amount → category → Save). Edit, delete, search, filter by type/month/category, and export to CSV.
- **Budgets** – weekly or monthly, for all spending or a single category. Shows what's left, what you can spend per day, and whether you're on track compared with how far through the period you are.
- **Savings goals** – target amount and optional date. Works out how much to save each week, fortnight and month, warns if that's more than you can realistically save, and estimates a finish date for a weekly amount.
- **Bills and reminders** – weekly, fortnightly, monthly, quarterly, yearly or one-off. Swipe to mark paid (records the expense and moves to the next due date) or skip. Local notifications at 9 am, on the day or up to a week before.
- **Payday planning** – what's safe to spend until your next pay after bills due before then, and a plan for your next pay (pay − bills in that cycle − planned savings).
- **Spending insights** – charts by category and by day, plus plain-English suggestions (eating out, subscriptions, shopping, groceries, transport, categories that jumped, saving rate).
- **What-if calculator** – change income or spending (with one-tap presets like "extra shift a week" or "rent up $30 a week") and see savings over 3 months to 2 years.
- **Reports** – income vs spending for the last 6 months or 8 weeks, a summary table, and this period vs last period by category.
- **Home-screen and Lock Screen widget** – available balance, budget left and next bill. Amounts can be hidden.
- **Light and dark mode**, Dynamic Type and VoiceOver labels throughout.

## Privacy

- No bank connections, accounts, analytics, ads or network access. Everything is entered manually.
- Data is stored in a single file in the app's private container, written with iOS **Complete File Protection** (encrypted while the iPhone is locked).
- Optional **Face ID / Touch ID / passcode lock**. The screen is hidden in the app switcher.
- The widget only receives totals, never individual transactions, and can hide amounts.

## Sample data

On first launch choose **Explore with sample data** or **Start with my own data**.

Sample records (a uni student working part-time in Sydney) are marked with an orange **SAMPLE** tag, and a banner appears while any sample data exists. **Remove sample data** (on the banner or in Settings) deletes only sample records; anything you've entered is kept. Editing a sample record turns it into your own.

## Backup, export and import

Settings → Backup & export:

- **Export transactions (CSV)** – opens in Excel, Numbers or Google Sheets.
- **Back up all data** – a JSON file you can save to Files or iCloud Drive.
- **Restore from backup** – replaces everything with a backup.
- **Import transactions (CSV)** – needs `Date` (dd/mm/yyyy) and `Amount` columns. `Type`, `Category` and `Description` are optional. Without a `Type` column, negative amounts are treated as spending.

## Running the app

Requirements: a Mac with **Xcode 16 or later**. The app targets iOS 17+.

1. Open `BudgetPlanner.xcodeproj`.
2. In `Config/Base.xcconfig`, change `BUNDLE_ID_PREFIX` from `com.example` to something unique, such as `com.yourname`.
3. Select the **BudgetPlanner** target → *Signing & Capabilities* → choose your Team. Do the same for **BudgetWidgetExtension**.
4. Choose an iPhone simulator or your device and press **Run** (⌘R). Press ⌘U to run the unit tests.

**Free Apple ID (Personal Team)?** Personal teams can't use App Groups, which the widget uses to read the summary. If signing fails, remove the *App Groups* capability from both targets (or clear `CODE_SIGN_ENTITLEMENTS` in their build settings). The app works the same; the widget will just ask you to open the app.

## How the numbers are worked out

All calculations live in `BudgetPlanner/Core/FinanceEngine.swift` and use `Decimal` to avoid rounding errors.

- **Available now** = starting balance + income − spending (up to today) − money moved into savings goals. Future-dated entries aren't counted until their date.
- **Safe to spend until payday** = available now − bills due from today until the day before payday (overdue bills included). Divided by the days left for a daily figure.
- **Budget status** – *Over budget* when spending is above the limit; *Spending fast* when the share spent is more than 10 points ahead of the share of the period that has passed; otherwise *On track*.
- **Usual month** – income and spending over up to the last 90 days, scaled to an average month (30.44 days).
- **Realistic savings** – 80% of your usual monthly surplus, rounded down to $10, leaving a buffer for irregular costs.
- **Goal plans** – remaining amount ÷ days to the target date, × 7, 14 or 30.44, rounded up to the dollar.
- **Repeating dates** are always counted from the first due date, so a bill due on the 31st falls on the last day of shorter months without drifting.

## Project structure

```
BudgetPlanner/
  App/            App entry point, tab navigation, lock handling
  Core/           Models, FinanceEngine, CSV, sample data (Foundation only, unit tested)
  Store/          DataStore (persistence, backup), bill reminders, Face ID lock
  Views/          Dashboard, Transactions, Plan (budgets, bills, goals, payday),
                  Insights (spending, reports, what-if), Settings, shared components
Shared/           Formatting and widget snapshot, used by the app and the widget
BudgetWidget/     WidgetKit extension
BudgetPlannerTests/  Unit tests for calculations, schedules, CSV and sample data
Config/           Build settings, entitlements, widget Info.plist
```

The Xcode project uses folder-synced groups, so new files added to these folders are picked up automatically.
