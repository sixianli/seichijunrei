import SwiftUI
import SeichiCore

/// 设置：App 内切换语言、默认导航地图、数据与版权说明。
struct SettingsView: View {
    @Environment(AppLanguage.self) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var mapApp: MapApp? = MapApp.preferred
    @State private var community = CommunityService.shared

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "–"
        let b = info?["CFBundleVersion"] as? String ?? "–"
        return "\(v) (\(b))"
    }

    var body: some View {
        @Bindable var language = language
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $language.override) {
                        Text(L("settings.followSystem")).tag(String?.none)
                        ForEach(AppLanguage.supported, id: \.self) { code in
                            Text(AppLanguage.nativeName(code)).tag(String?.some(code))
                        }
                    } label: {
                        Label(L("settings.language"), systemImage: "globe")
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("settingsLanguage")
                } footer: {
                    Text(L("settings.languageFooter"))
                }

                Section {
                    Picker(selection: $mapApp) {
                        Text(L("settings.askEveryTime")).tag(MapApp?.none)
                        ForEach(MapApp.ordered) { app in
                            Text(app.name).tag(MapApp?.some(app))
                        }
                    } label: {
                        Label(L("settings.mapApp"), systemImage: "map")
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("settingsMapApp")
                    .onChange(of: mapApp) { _, v in MapApp.preferred = v }
                } footer: {
                    Text(L("settings.mapAppFooter"))
                }

                Section(L("settings.community")) {
                    NavigationLink {
                        MySubmissionsView()
                    } label: {
                        Label(L("submit.mine"), systemImage: "tray.full")
                    }
                    .accessibilityIdentifier("openMySubmissions")
                    if !community.blockedUsers.isEmpty {
                        Button(role: .destructive) { community.unblockAll() } label: {
                            Label(L("community.unblockAll", community.blockedUsers.count), systemImage: "hand.raised.slash")
                        }
                    }
                    if let email = AppConfig.contactEmail,
                       let url = URL(string: "mailto:\(email)?subject=Seichi%20Junrei") {
                        Link(destination: url) {
                            LabeledContent {
                                Text(email).font(.footnote)
                            } label: {
                                Label(L("settings.contact"), systemImage: "envelope")
                            }
                        }
                        .accessibilityIdentifier("settingsContact")
                    }
                }

                Section(L("settings.copyrightTitle")) {
                    Text(L("settings.copyrightBody"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let email = AppConfig.contactEmail,
                       let url = URL(string: "mailto:\(email)?subject=Copyright%20complaint") {
                        Link(destination: url) { Label(email, systemImage: "envelope").font(.footnote) }
                    }
                }

                Section(L("settings.credits")) {
                    Text(L("settings.creditsBody"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent(L("settings.version"), value: appVersion)
                }
            }
            .navigationTitle(L("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) { dismiss() } }
            }
        }
    }
}
