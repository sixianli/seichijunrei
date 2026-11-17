import AVFoundation
import Observation
import UIKit
import Vision
import QuartzCore
import SeichiCore

/// 后置相机预览 + 拍照留念。帮拍模式下还会实时检测画面里的人（Vision）。
@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "seichi.camera.session")
    private let visionQueue = DispatchQueue(label: "seichi.camera.vision")
    @ObservationIgnored private var configured = false

    /// 是否检测画面中的人物（帮拍模式），需要在 start() 之前设置
    @ObservationIgnored var detectsPeople = false
    /// 画面中最显眼的人物外接框（归一化，原点左上，相对竖屏的相机画面）
    private(set) var subjectBox: UnitRect?
    @ObservationIgnored private var lastDetection: CFTimeInterval = 0
    @ObservationIgnored private var device: AVCaptureDevice?
    /// 当前变焦倍数（相对广角镜头）
    private(set) var zoomFactor: Double = 1
    /// 可用的变焦范围（帮拍模式的自动变焦只在这个范围里微调，避免画质过差）
    private(set) var zoomRange: ClosedRange<Double> = 1...1
    @ObservationIgnored private var missedFrames = 0

    /// 拍照完成后回调（主线程）
    @ObservationIgnored var onPhotoCaptured: ((UIImage) -> Void)?
    /// 拍完是否自动存相册。帮拍模式会先自动裁切构图，再自己调用 save(_:)
    @ObservationIgnored var savesAutomatically = true

    private(set) var isAuthorized = false
    private(set) var statusMessage: String?
    /// 传感器长边视场角与长宽比，用于把名场面方向投影到画面上
    private(set) var sensorFOV: Double = 0
    private(set) var sensorAspect: Double = 4.0 / 3.0

    func start() {
        #if DEBUG
        // UI 测试 / 模拟器：SEICHI_SIM_SUBJECT="centerX,footY,height" 模拟检测到的人
        if let raw = ProcessInfo.processInfo.environment["SEICHI_SIM_SUBJECT"] {
            let v = raw.split(separator: ",").compactMap { Double($0) }
            if v.count == 3 { subjectBox = SubjectFraming(centerX: v[0], footY: v[1], height: v[2]).box(aspect: 0.75) }
        }
        #endif
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
                    self.device = device
                    let maxZoom = min(Double(device.maxAvailableVideoZoomFactor), 2.5)
                    DispatchQueue.main.async { self.zoomRange = 1...max(1, maxZoom) }
                    let fov = Double(device.activeFormat.videoFieldOfView)
                    let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                    let aspect = Double(max(dims.width, dims.height)) / Double(max(1, min(dims.width, dims.height)))
                    DispatchQueue.main.async {
                        self.sensorFOV = fov
                        self.sensorAspect = aspect
                    }
                }
                if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
                if detectsPeople, session.canAddOutput(videoOutput) {
                    videoOutput.alwaysDiscardsLateVideoFrames = true
                    videoOutput.setSampleBufferDelegate(self, queue: visionQueue)
                    session.addOutput(videoOutput)
                    // 让送给 Vision 的画面也是竖屏，坐标与预览一致
                    if let c = videoOutput.connection(with: .video), c.isVideoRotationAngleSupported(90) {
                        c.videoRotationAngle = 90
                    }
                }
                session.commitConfiguration()
                configured = true
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func capturePhoto() {
        #if targetEnvironment(simulator)
        // 模拟器没有相机：生成一张示意照片，便于调试分享卡
        let image = SimulatedImages.photo()
        statusMessage = L("camera.saved")
        onPhotoCaptured?(image)
        return
        #else
        guard isAuthorized else { return }
        sessionQueue.async { [self] in
            if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90   // 竖屏
            }
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
        #endif
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async { self.statusMessage = L("camera.failed") }
            return
        }
        if savesAutomatically { save(image) }
        DispatchQueue.main.async { self.onPhotoCaptured?(image) }
    }

    /// 存入相册（完成后在 statusMessage 里提示）
    func save(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?,
                             contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            self.statusMessage = error == nil ? L("camera.saved") : L("camera.saveFailed")
        }
    }

    func clearStatus() { statusMessage = nil }

    /// 平滑地变焦到指定倍数
    func setZoom(_ factor: Double, rate: Float = 6) {
        let z = min(max(factor, zoomRange.lowerBound), zoomRange.upperBound)
        zoomFactor = z
        sessionQueue.async { [weak self] in
            guard let device = self?.device, (try? device.lockForConfiguration()) != nil else { return }
            device.ramp(toVideoZoomFactor: CGFloat(z), withRate: rate)
            device.unlockForConfiguration()
        }
    }

    // MARK: - 人物检测（帮拍模式）

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // 每秒约 6 次足够给出指引，也省电
        let now = CACurrentMediaTime()
        guard now - lastDetection > 0.16, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastDetection = now
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([request])
        let best = (request.results ?? [])
            .filter { $0.confidence > 0.3 }
            .max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
        // Vision 的坐标原点在左下角，转成左上角
        let box = best.map { b in
            UnitRect(x: Double(b.boundingBox.minX), y: Double(1 - b.boundingBox.maxY),
                           width: Double(b.boundingBox.width), height: Double(b.boundingBox.height))
        }
        DispatchQueue.main.async { self.updateSubject(box) }
    }

    private func updateSubject(_ box: UnitRect?) {
        guard let box else {
            // 偶尔漏检一两帧时保留上一次结果，避免提示来回跳
            missedFrames += 1
            if missedFrames >= 4 { subjectBox = nil }
            return
        }
        missedFrames = 0
        if let old = subjectBox {
            // 简单的低通平滑
            func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * 0.5 }
            subjectBox = UnitRect(x: mix(old.x, box.x), y: mix(old.y, box.y),
                                  width: mix(old.width, box.width), height: mix(old.height, box.height))
        } else {
            subjectBox = box
        }
    }
}
