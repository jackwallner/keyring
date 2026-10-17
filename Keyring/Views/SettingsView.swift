import StoreKit
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var garage: GarageStore
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var sharing: SharingService
    @EnvironmentObject private var community: CommunityPhotos
    @Environment(\.openURL) private var openURL

    @AppStorage(AppGroup.Key.hideCosts, store: AppGroup.defaults) private var hideCosts = false
    @AppStorage(AppGroup.Key.appearance, store: AppGroup.defaults) private var appearance = Appearance.system.rawValue

    @State private var name = ""
    @State private var garageName = ""
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var reminderTime = Date.now
    @State private var showingPaywall = false
    @State private var showingFamily = false
    @State private var exportFile: SharedFile?

    var body: some View {
        Form {
            proSection

            Section {
                LabeledContent("Your name") {
                    TextField("For entries you log", text: $name)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { garage.setOwnerName(name) }
                }
                if let own = garage.ownGarage {
                    LabeledContent("Garage name") {
                        TextField("Our garage", text: $garageName)
                            .multilineTextAlignment(.trailing)
                            .onSubmit {
                                own.name = garageName.trimmed.nilIfEmpty ?? "Our garage"
                                garage.saveVehicleEdits()
                            }
                    }
                }
                Button { showingFamily = true } label: {
                    HStack {
                        Label("Family sharing", systemImage: "person.2.fill")
                        Spacer()
                        Text(sharing.share == nil ? "Off" : Format.count(sharing.participantNames.count + 1, "person", "people"))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                .foregroundStyle(Theme.ink)
            } header: {
                Text("Garage")
            } footer: {
                Text("Your name signs the jobs you log so the family knows who did what.")
            }

            Section {
                switch notificationStatus {
                case .denied:
                    Button("Turn on in iPhone Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                case .notDetermined:
                    Button("Turn on reminders") {
                        Task {
                            _ = await ReminderScheduler.shared.requestAuthorization()
                            await refreshNotifications()
                            ReminderScheduler.shared.schedule(for: garage)
                        }
                    }
                default:
                    DatePicker("Remind me at", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .onChange(of: reminderTime) { _, time in
                            ReminderScheduler.shared.setReminderHour(Calendar.current.component(.hour, from: time), store: garage)
                        }
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("A heads-up a week before each job and on the day, plus one Saturday note if anything is overdue. Reminders are per iPhone; mute a vehicle on its page.")
            }

            Section {
                Toggle("Hide costs on this iPhone", isOn: $hideCosts)
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("This iPhone")
            } footer: {
                Text("Hiding costs keeps prices off lists, the garage and the Service Record here. Everyone else still sees what they choose.")
            }

            Section {
                Button {
                    if let url = try? CSVExport.url(for: garage.vehicles + garage.retiredVehicles) { exportFile = SharedFile(url: url) }
                } label: {
                    Label("Export everything (CSV)", systemImage: "tablecells")
                }
                if !garage.retiredVehicles.isEmpty {
                    NavigationLink { RetiredVehiclesView() } label: { Label("Sold and retired", systemImage: "archivebox") }
                }
                if !community.blockedAuthors.isEmpty {
                    Button("Unblock \(Format.count(community.blockedAuthors.count, "person", "people")) in photos") { community.unblockAll() }
                }
            } header: {
                Text("Your data")
            } footer: {
                Text("Everything lives in your iCloud. The spreadsheet is always free, so your history is always yours.")
            }

            Section("Keyring") {
                Button { openURL(AppLinks.writeReview) } label: { Label("Rate Keyring", systemImage: "star") }
                Button { openURL(AppLinks.feedback) } label: { Label("Send feedback", systemImage: "envelope") }
                ShareLink(item: AppLinks.shareApp, message: Text("Keyring keeps our maintenance for every vehicle in one place.")) {
                    Label("Tell a friend", systemImage: "square.and.arrow.up")
                }
                Button { openURL(AppLinks.support) } label: { Label("Help", systemImage: "questionmark.circle") }
            }
            .foregroundStyle(Theme.ink)

            Section {
                Link("Privacy Policy", destination: AppLinks.privacyPolicy)
                Link("Terms of Use", destination: AppLinks.standardEULA)
                Link("Community guidelines", destination: AppLinks.communityGuidelines)
            } footer: {
                Text("Maintenance intervals are typical figures for normal use, not manufacturer schedules. Always follow your owner's manual. Keyring is not an official aircraft or vessel logbook and doesn't replace one.\n\nKeyring \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
            }
            .foregroundStyle(Theme.ink)

            #if DEBUG
            Section("Debug") {
                Toggle("Pro (local)", isOn: Binding(get: { store.isPro }, set: { store.setLocalOverride(isPro: $0) }))
            }
            #endif
        }
        .paperBackground()
        .navigationTitle("Settings")
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .sheet(isPresented: $showingFamily) { NavigationStack { FamilyView() } }
        .sheet(item: $exportFile) { file in ShareSheet(items: [file.url]) }
        .task {
            name = garage.ownerName ?? ""
            garageName = garage.ownGarage?.name ?? ""
            reminderTime = Calendar.current.date(bySettingHour: ReminderScheduler.shared.reminderHour, minute: 0, second: 0, of: .now) ?? .now
            await refreshNotifications()
        }
        .onDisappear {
            garage.setOwnerName(name)
            if let own = garage.ownGarage, own.name != garageName.trimmed, !garageName.trimmed.isEmpty {
                own.name = garageName.trimmed
                garage.saveVehicleEdits()
            }
        }
    }

    @ViewBuilder
    private var proSection: some View {
        Section {
            if store.isPro {
                HStack {
                    Label("Keyring Pro", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.brass)
                    Spacer()
                    Link("Manage", destination: AppLinks.manageSubscriptions).font(.subheadline.weight(.semibold))
                }
            } else {
                Button { showingPaywall = true } label: {
                    HStack(spacing: Theme.sm) {
                        Image(systemName: "key.horizontal.fill")
                            .foregroundStyle(Theme.brass)
                            .frame(width: 40, height: 40)
                            .background(Theme.brassSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keyring Pro").font(.headline).foregroundStyle(Theme.ink)
                            Text("Every vehicle, the Service Record, receipt reading and insights")
                                .font(.footnote).foregroundStyle(Theme.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.faintInk)
                    }
                }
                .accessibilityIdentifier("settings.pro")
            }
        }
    }

    private func refreshNotifications() async {
        notificationStatus = await ReminderScheduler.shared.authorizationStatus()
    }
}
