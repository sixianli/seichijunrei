import SwiftUI
import UIKit
import SeichiCore

/// 用户在现场校准机位：站到动画画面的拍摄位置，让摄像头朝向与画面一致，然后提交。
struct CalibrationView: View {
    let spot: Spot

    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var orientation = OrientationService()
    @State private var note = ""
    @State private var submitting = false
    @State private var result: CalibrationService.SubmitResult?
    @State private var lastSubmission: CalibrationSubmission?
    @State private var copied = false

    private var reading: CalibrationReading? {
        guard let loc = location.lastLocation else { return nil }
        return CalibrationReading(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                                  horizontalAccuracy: loc.horizontalAccuracy,
                                  heading: orientation.heading, headingAccuracy: orientation.accuracy,
                                  pitch: orientation.pitch)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        SceneArtwork(spot: spot, compact: true)
                            .frame(width: 96, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(spot.workTitle).font(.caption).foregroundStyle(.secondary)
                            Text(spot.quotedSceneTitle).font(.headline)
                            Text(spot.placeName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Text(L("calib.intro")).font(.callout)

                    if let result {
                        resultView(result)
                    } else {
                        readingsCard
                        noteField
                        Text(L("calib.privacy")).font(.caption).foregroundStyle(.secondary)
                        submitButton
                    }
                }
                .padding()
            }
            .navigationTitle(L("calib.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }.accessibilityIdentifier("closeCalibration")
                }
            }
            .onAppear {
                orientation.declinationProvider = { [location] in location.declination }
                orientation.compassFallback = { [location] in (location.compassHeading, location.headingAccuracy) }
                orientation.start()
            }
            .onDisappear { orientation.stop() }
        }
    }

    // MARK: - 实时读数

    private var readingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let r = reading {
                row("location.fill", L("calib.accuracy", Int(max(r.horizontalAccuracy, 0).rounded())),
                    ok: r.horizontalAccuracy >= 0 && r.horizontalAccuracy <= CalibrationQuality.maxGPSAccuracy)
                if let h = r.heading {
                    row("safari", L("calib.heading", Compass.name(h), Int(h.rounded()) % 360,
                                    Int(max(r.headingAccuracy, 0).rounded())),
                        ok: r.headingAccuracy >= 0 && r.headingAccuracy <= CalibrationQuality.maxHeadingAccuracy)
                } else {
                    row("safari", L("calib.headingNone"), ok: false)
                }
                if let p = r.pitch {
                    row("arrow.up.and.down", L("calib.pitch", Int(p.rounded())), ok: true)
                }
                row("mappin.and.ellipse",
                    L("calib.distance", NearbySearch.formatDistance(GeoMath.distance(from: r.point, to: spot.coordinate))),
                    ok: nil)

                let issues = CalibrationQuality.issues(for: r, listed: spot.coordinate)
                if issues.isEmpty {
                    Label(L("calib.good"), systemImage: "checkmark.seal.fill")
                        .font(.subheadline.bold()).foregroundStyle(.green)
                } else {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Label(text(for: issue), systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            } else {
                HStack { ProgressView(); Text(L("scene.locating")) }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calibrationReadings")
    }

    private func row(_ symbol: String, _ text: String, ok: Bool?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 22)
            Text(text).font(.subheadline.monospacedDigit())
            Spacer()
            if let ok {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(ok ? .green : .orange)
            }
        }
    }

    private func text(for issue: CalibrationIssue) -> String {
        switch issue {
        case .poorGPS: return L("calib.issue.gps")
        case .poorCompass: return L("calib.issue.compass")
        case .noHeading: return L("calib.issue.noHeading")
        case .farFromListed: return L("calib.issue.far")
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("calib.noteLabel")).font(.subheadline.bold())
            TextField(L("calib.notePlaceholder"), text: $note, axis: .vertical)
                .lineLimit(2...5)
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("calibrationNote")
        }
    }

    private var submitButton: some View {
        Button {
            guard let r = reading else { return }
            let s = CalibrationSubmission(spotID: spot.id, reading: r, note: note,
                                          appVersion: CalibrationService.appVersion,
                                          locale: Locale.current.identifier)
            lastSubmission = s
            submitting = true
            Task {
                let outcome = await CalibrationService.shared.submit(s)
                submitting = false
                withAnimation { result = outcome }
            }
        } label: {
            HStack {
                if submitting { ProgressView() }
                Text(L("calib.submit")).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .glassButton(prominent: true, tint: spot.tintColor)
        .controlSize(.large)
        .disabled(submitting || !(reading.map(CalibrationQuality.canSubmit) ?? false))
        .accessibilityIdentifier("submitCalibration")
    }

    // MARK: - 结果

    @ViewBuilder
    private func resultView(_ result: CalibrationService.SubmitResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch result {
            case .submitted:
                Label(L("calib.thanks"), systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(.green)
                    .accessibilityIdentifier("calibrationThanks")
            case .queued:
                Label(L("calib.queued"), systemImage: "clock.arrow.circlepath").font(.headline)
            case .noAccount:
                Label(L("calib.noAccount"), systemImage: "icloud.slash").font(.headline)
                copyButton
            case .failed(let reason):
                Label(L("calib.failed", reason), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.orange)
                copyButton
            }
            Button(L("common.done")) { dismiss() }
                .glassButton()
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var copyButton: some View {
        Button {
            if let s = lastSubmission { UIPasteboard.general.string = CalibrationService.json(for: s) }
            copied = true
        } label: {
            Label(copied ? L("calib.copied") : L("calib.copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .glassButton()
    }
}
