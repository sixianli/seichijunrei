import SwiftUI
import SeichiCore

/// 设置：App 内切换语言、默认导航地图、数据与版权说明。
struct SettingsView: View {
    @Environment(AppLanguage.self) private var language
    @Environment(SpotStore.self) private var store
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
                    .onChange(of: mapApp) { _, v in MapApp.preferred = v }
                } footer: {
                    Text(L("settings.mapAppFooter"))
                }

                Section(L("settings.data")) {
                    LabeledContent(L("settings.sceneCount"), value: "\(store.spots.count)")
                    LabeledContent(L("settings.workCount"),
                                   value: "\(Set(store.spots.map(\.workID)).count)")
                    Text(L("settings.calibrationNote"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(L("settings.community")) {
                    NavigationLink {
                        MySubmissionsView()
                    } label: {
                        Label(L("submit.mine"), systemImage: "tray.full")
                    }
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

/// “导航到这里”：按设置里的默认地图直接打开，否则让用户选（Google / Apple / 高德 / 百度）。
struct DirectionsButton: View {
    let spot: Spot
    @State private var choosing = false

    var body: some View {
        Button {
            if let app = MapApp.preferred { app.openDirections(to: spot) } else { choosing = true }
        } label: {
            Label(L("detail.openMaps"), systemImage: "arrow.triangle.turn.up.right.diamond")
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("openDirections")
        .confirmationDialog(L("detail.chooseMapApp"), isPresented: $choosing, titleVisibility: .visible) {
            ForEach(MapApp.ordered) { app in
                Button(app.isInstalled ? app.name : L("mapApp.web", app.name)) { app.openDirections(to: spot) }
            }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("detail.chooseMapAppHint"))
        }
    }
}
