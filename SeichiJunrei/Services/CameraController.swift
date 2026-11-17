import AVFoundation
import Observation
import UIKit

/// 后置相机预览 + 拍照留念。
@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "seichi.camera.session")
    @ObservationIgnored private var configured = false

    private(set) var isAuthorized = false
    private(set) var statusMessage: String?
    /// 传感器长边视场角与长宽比，用于把名场面方向投影到画面上
    private(set) var sensorFOV: Double = 0
    private(set) var sensorAspect: Double = 4.0 / 3.0

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.isAuthorized = granted
                    if granted { self.configureAndRun() }
                }
            }
        default:
            isAuthorized = false
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [self] in
            if !configured {
                session.beginConfiguration()
                session.sessionPreset = .photo
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                    let fov = Double(device.activeFormat.videoFieldOfView)
                    let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                    let aspect = Double(max(dims.width, dims.height)) / Double(max(1, min(dims.width, dims.height)))
                    DispatchQueue.main.async {
                        self.sensorFOV = fov
                        self.sensorAspect = aspect
                    }
                }
                if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
                session.commitConfiguration()
                configured = true
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func capturePhoto() {
        guard isAuthorized else { return }
        sessionQueue.async { [self] in
            if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90   // 竖屏
            }
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async { self.statusMessage = "拍照失败" }
            return
        }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        DispatchQueue.main.async { self.statusMessage = "已保存到相册 📸" }
    }

    func clearStatus() { statusMessage = nil }
}
