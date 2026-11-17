import SwiftUI

@main
struct SeichiJunreiApp: App {
    @State private var store = SpotStore()
    @State private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(location)
                .task {
                    store.load()
                    location.start()
                    NotificationService.shared.requestAuthorization()
                    NotificationService.shared.onOpenSpot = { id in store.requestedSpotID = id }
                }
                .onChange(of: location.lastLocation) { _, newValue in
                    guard let loc = newValue else { return }
                    store.update(userLocation: loc)
                    location.monitorNearestRegions(store.nearby.map(\.spot))
                }
        }
    }
}
