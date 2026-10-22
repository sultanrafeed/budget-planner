import SwiftUI

/// First-launch welcome: explore with sample data or start fresh.
struct OnboardingView: View {
    @Environment(DataStore.self) private var store
    @State private var startingFresh = false
    @State private var balanceText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Theme.accent)
                        Text("Budget Planner")
                            .font(.largeTitle.bold())
                        Text("A simple way to see what you have, where it goes, and how much you can save.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    VStack(alignment: .leading, spacing: 18) {
                        feature("banknote", "Know what's available", "See your balance and what's safe to spend until payday.")
                        feature("chart.pie.fill", "See where it goes", "Clear charts and practical ideas to spend less.")
                        feature("calendar.badge.clock", "Stay ahead of bills", "Reminders before rent, phone and subscriptions are due.")
                        feature("target", "Save with a plan", "Goals that tell you how much to put aside each week.")
                        feature("lock.shield.fill", "Private by design", "Everything stays on your iPhone. No bank logins, no accounts.")
                    }

                    if startingFresh {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("How much money do you have right now?")
                                .font(.headline)
                            Text("Add up your everyday accounts. You can skip this and change it later in Settings.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            AmountField(title: "0.00", text: $balanceText, large: true)
                                .padding(12)
                                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Button {
                                finish(withSample: false)
                            } label: {
                                Text("Start budgeting").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        .transition(.opacity)
                    } else {
                        VStack(spacing: 12) {
                            Button {
                                withAnimation { startingFresh = true }
                            } label: {
                                Text("Start with my own data").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                            Button {
                                finish(withSample: true)
                            } label: {
                                Text("Explore with sample data").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)

                            Text("Sample data is clearly marked and can be removed at any time.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .interactiveDismissDisabled()
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func finish(withSample: Bool) {
        if withSample {
            store.loadSampleData()
        } else if let amount = AmountInput.parse(balanceText), amount > 0 {
            store.updateSettings {
                $0.openingBalance = amount
                $0.openingBalanceIsSample = false
            }
        }
        store.updateSettings { $0.hasOnboarded = true }
    }
}

#Preview {
    OnboardingView().environment(DataStore(fileURL: nil))
}
