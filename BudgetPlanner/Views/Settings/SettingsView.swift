import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(DataStore.self) private var store
    @Environment(AppLock.self) private var lock
    @Environment(\.openURL) private var openURL

    private enum ImportKind { case backup, csv }

    @State private var editingPay = false
    @State private var editingOpening = false
    @State private var exported: ExportedFile?
    @State private var importKind: ImportKind?
    @State private var showImporter = false
    @State private var confirmRestore: URL?
    @State private var confirmErase = false
    @State private var confirmRemoveSample = false
    @State private var notice: String?
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                moneySection
                privacySection
                remindersSection
                dataSection
                sampleSection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $editingPay) { PayScheduleForm() }
            .sheet(isPresented: $editingOpening) { OpeningBalanceForm() }
            .sheet(item: $exported) { file in
                ShareSheet(items: [file.url]).presentationDetents([.medium, .large])
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: importKind == .csv ? [.commaSeparatedText, .plainText] : [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .confirmationDialog("Replace all data with this backup?", isPresented: Binding(
                get: { confirmRestore != nil },
                set: { if !$0 { confirmRestore = nil } }
            ), titleVisibility: .visible) {
                Button("Restore backup", role: .destructive) {
                    guard let url = confirmRestore else { return }
                    do {
                        try store.restoreBackup(from: url)
                        notice = "Backup restored."
                    } catch {
                        store.errorMessage = error.localizedDescription
                    }
                }
            } message: {
                Text("Everything currently in the app will be replaced. Consider making a backup first.")
            }
            .confirmationDialog("Erase all data?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) {
                    store.eraseAllData()
                    lock.disable()
                }
            } message: {
                Text("This deletes every transaction, bill, budget and goal from this iPhone. It can't be undone.")
            }
            .confirmationDialog("Remove all sample data?", isPresented: $confirmRemoveSample, titleVisibility: .visible) {
                Button("Remove sample data", role: .destructive) { store.removeSampleData() }
            } message: {
                Text("Only sample records are removed. Anything you've entered yourself is kept.")
            }
            .alert("Done", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(notice ?? "")
            }
        }
    }

    // MARK: Sections

    private var moneySection: some View {
        Section {
            Button { editingOpening = true } label: {
                LabeledContent("Starting balance") {
                    HStack(spacing: 6) {
                        if store.settings.openingBalanceIsSample { SampleBadge() }
                        Text(store.settings.openingBalance.currency)
                    }
                }
            }
            .tint(.primary)
            Button { editingPay = true } label: {
                LabeledContent("Payday") {
                    if let pay = store.settings.pay {
                        Text("\(pay.amount.currencyWhole) \(pay.frequency.title.lowercased())")
                    } else {
                        Text("Not set")
                    }
                }
            }
            .tint(.primary)
        } header: {
            Text("Money")
        } footer: {
            Text("Starting balance is what you had in your accounts when you began using the app. Your available balance adds income and subtracts spending from there.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.settings.appLockEnabled },
                set: { newValue in
                    Task {
                        // Confirm it's really the owner before changing the lock.
                        guard await lock.authenticate(reason: newValue ? "Turn on app lock" : "Turn off app lock") else { return }
                        store.updateSettings { $0.appLockEnabled = newValue }
                    }
                }
            )) {
                Label("Lock with \(AppLock.methodName)", systemImage: "lock.fill")
            }
            .disabled(!AppLock.isAvailable)

            Toggle(isOn: Binding(
                get: { store.settings.hideWidgetAmounts },
                set: { newValue in store.updateSettings { $0.hideWidgetAmounts = newValue } }
            )) {
                Label("Hide amounts on widget", systemImage: "eye.slash")
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Your information stays on this iPhone and is encrypted by iOS while your phone is locked. There are no accounts, bank logins, ads or tracking. The app never connects to your bank.")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.settings.billRemindersEnabled },
                set: { newValue in
                    store.updateSettings { $0.billRemindersEnabled = newValue }
                    if newValue {
                        Task { notificationsDenied = !(await store.requestReminderPermission()) }
                    }
                }
            )) {
                Label("Bill reminders", systemImage: "bell.fill")
            }
            if notificationsDenied {
                Button("Allow notifications in iPhone Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Choose when to be reminded for each bill in Plan → Bills.")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                export { try store.csvFile() }
            } label: {
                Label("Export transactions (CSV)", systemImage: "tablecells")
            }
            .disabled(store.data.transactions.isEmpty)

            Button {
                export { try store.backupFile() }
            } label: {
                Label("Back up all data", systemImage: "externaldrive.badge.checkmark")
            }

            Button {
                importKind = .backup
                showImporter = true
            } label: {
                Label("Restore from backup", systemImage: "arrow.clockwise.icloud")
            }

            Button {
                importKind = .csv
                showImporter = true
            } label: {
                Label("Import transactions (CSV)", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Backup & export")
        } footer: {
            Text("Save backups to Files or iCloud Drive. CSV files open in Excel, Numbers and Google Sheets. To import, use columns Date (dd/mm/yyyy), Description and Amount – negative amounts are spending.")
        }
    }

    private var sampleSection: some View {
        Section {
            if store.data.hasSampleData {
                Button("Remove sample data", role: .destructive) { confirmRemoveSample = true }
            } else {
                Button("Load sample data") { store.loadSampleData() }
            }
            Button("Erase all data", role: .destructive) { confirmErase = true }
        } header: {
            Text("Sample data")
        } footer: {
            Text(store.data.hasSampleData
                 ? "Sample records are marked SAMPLE. Removing them keeps everything you've entered."
                 : "Load sample data to explore the app. It's clearly marked and can be removed in one tap.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            LabeledContent("Currency", value: "Australian dollars (AUD)")
            LabeledContent("Date format", value: "dd/mm/yyyy")
            LabeledContent("Weeks start on", value: "Monday")
        }
    }

    // MARK: Actions

    private func export(_ make: () throws -> URL) {
        do {
            exported = ExportedFile(url: try make())
        } catch {
            store.errorMessage = "Couldn't create the file. \(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            store.errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            switch importKind {
            case .backup:
                confirmRestore = url
            case .csv:
                do {
                    let counts = try store.importCSV(from: url)
                    notice = "Imported \(counts.imported) transactions." + (counts.skipped > 0 ? " \(counts.skipped) rows couldn't be read and were skipped." : "")
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            case nil:
                break
            }
        }
    }
}

struct OpeningBalanceForm: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isNegative = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(title: "0.00", text: $text, large: true)
                    Toggle("I'm in overdraft (negative balance)", isOn: $isNegative)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let problem { Text(problem).foregroundStyle(Theme.danger) }
                        Text("Add up the everyday accounts you spend from. Don't include money already in savings goals.")
                    }
                }
            }
            .navigationTitle("Starting balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !text.isEmpty, let problem = AmountInput.problem(with: text, allowZero: true) {
                            self.problem = problem
                            return
                        }
                        let amount = AmountInput.parse(text) ?? 0
                        store.updateSettings {
                            $0.openingBalance = isNegative ? -amount : amount
                            $0.openingBalanceIsSample = false
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                let current = store.settings.openingBalance
                isNegative = current < 0
                text = AmountInput.text(for: current < 0 ? -current : current)
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    SettingsView()
        .environment(DataStore.preview())
        .environment(AppLock(enabled: false))
}
