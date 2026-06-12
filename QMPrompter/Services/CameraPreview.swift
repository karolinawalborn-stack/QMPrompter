import AVFoundation
import MetalKit
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    @Binding var permissionState: CameraPermissionState

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        context.coordinator.attach(to: view)
        context.coordinator.requestAndStart()
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        context.coordinator.attach(to: uiView)
    }

    static func dismantleUIView(_ uiView: PreviewContainerView, coordinator: CameraCoordinator) {
        coordinator.invalidate()
        uiView.previewLayer.session = nil
    }

    func makeCoordinator() -> CameraCoordinator {
        CameraCoordinator(permissionState: $permissionState)
    }
}

enum CameraPermissionState: Equatable {
    case checking
    case authorized
    case denied
    case unavailable
}

final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class CameraCoordinator: NSObject {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.qiaomu.prompter.camera")
    private var didConfigure = false
    private weak var previewView: PreviewContainerView?
    private var permissionState: Binding<CameraPermissionState>
    private var isActive = true
    private var isInvalidated = false

    init(permissionState: Binding<CameraPermissionState>) {
        self.permissionState = permissionState
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        invalidate()
    }

    func attach(to view: PreviewContainerView) {
        previewView = view
        view.previewLayer.session = session
    }

    func requestAndStart() {
        guard !isInvalidated else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setPermissionState(.authorized)
            startSession()
        case .notDetermined:
            setPermissionState(.checking)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self, !self.isInvalidated else { return }
                self.setPermissionState(granted ? .authorized : .denied)
                if granted {
                    self.startSession()
                }
            }
        case .denied, .restricted:
            setPermissionState(.denied)
        @unknown default:
            setPermissionState(.unavailable)
        }
    }

    func stopSession() {
        let session = session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func invalidate() {
        isInvalidated = true
        isActive = false
        previewView?.previewLayer.session = nil
        previewView = nil
        stopSession()
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard isActive, !isInvalidated else { return }
            if !didConfigure {
                configureSession()
            }
            if didConfigure, !session.isRunning {
                session.startRunning()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium
        defer { session.commitConfiguration() }

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else {
            setPermissionState(.unavailable)
            return
        }

        session.addInput(input)
        didConfigure = true
    }

    private func setPermissionState(_ state: CameraPermissionState) {
        DispatchQueue.main.async { [weak self] in
            self?.permissionState.wrappedValue = state
        }
    }

    @objc private func handleWillResignActive() {
        isActive = false
        stopSession()
    }

    @objc private func handleDidBecomeActive() {
        guard !isInvalidated else { return }
        isActive = true
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            requestAndStart()
            return
        }
        setPermissionState(.authorized)
        startSession()
    }
}


// ========================================================================
// MARK: - Beauty Camera (Metal + Core Image filters)
// ========================================================================

struct BeautyConfig {
    var isEnabled = false
    var smoothing: Float = 0.3
    var brightness: Float = 0.08
}

struct BeautyCameraPreview: UIViewRepresentable {
    @Binding var permissionState: CameraPermissionState
    @Binding var config: BeautyConfig

    func makeCoordinator() -> BeautyCameraCoordinator {
        BeautyCameraCoordinator(permissionState: $permissionState, config: $config)
    }

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.framebufferOnly = false
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true
        mtkView.backgroundColor = .black
        mtkView.contentScaleFactor = UIScreen.main.scale
        mtkView.autoResizeDrawable = true
        context.coordinator.setup(mtkView: mtkView)
        return mtkView
    }

    func updateUIView(_ mtkView: MTKView, context: Context) {
        context.coordinator.config = config
    }

    static func dismantleUIView(_ mtkView: MTKView, coordinator: BeautyCameraCoordinator) {
        coordinator.invalidate()
    }
}

final class BeautyCameraCoordinator: NSObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.qiaomu.prompter.beauty")
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let ciContext: CIContext
    private let commandQueue: MTLCommandQueue
    private var metalDevice: MTLDevice
    private var latestCIImage: CIImage?
    private weak var mtkView: MTKView?
    private var permissionState: Binding<CameraPermissionState>
    var config: BeautyConfig
    private var isInvalidated = false
    private var didConfigure = false

    private let blurFilter = CIFilter(name: "CIGaussianBlur")!
    private let blendFilter = CIFilter(name: "CIBlendWithAlphaMask")!
    private let colorFilter = CIFilter(name: "CIColorControls")!

    init(permissionState: Binding<CameraPermissionState>, config: Binding<BeautyConfig>) {
        self.permissionState = permissionState
        self.config = config.wrappedValue
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not available on this device")
        }
        self.metalDevice = device
        self.ciContext = CIContext(mtlDevice: device, options: [
            CIContextOption.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            CIContextOption.highQualityDownsample: true
        ])
        self.commandQueue = device.makeCommandQueue()!
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        invalidate()
    }

    func setup(mtkView: MTKView) {
        self.mtkView = mtkView
        mtkView.delegate = self
        requestAndStart()
    }

    func requestAndStart() {
        guard !isInvalidated else { return }
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setPermissionState(.authorized)
            startSession()
        case .notDetermined:
            setPermissionState(.checking)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self, !self.isInvalidated else { return }
                DispatchQueue.main.async {
                    self.setPermissionState(granted ? .authorized : .denied)
                }
                if granted {
                    self.startSession()
                }
            }
        case .denied, .restricted:
            setPermissionState(.denied)
        @unknown default:
            setPermissionState(.unavailable)
        }
    }

    func invalidate() {
        isInvalidated = true
        mtkView?.delegate = nil
        mtkView = nil
        stopSession()
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            if self?.session.isRunning == true { self?.session.stopRunning() }
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !isInvalidated else { return }
            if !didConfigure {
                configureSession()
            }
            if didConfigure, !session.isRunning { session.startRunning() }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium
        defer { session.commitConfiguration() }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input)
        else {
            setPermissionState(.unavailable)
            return
        }
        session.addInput(input)
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }
        // 延迟设置连接属性，等 session 稳定后再配置
        if let connection = videoDataOutput.connection(with: .video) {
            connection.isVideoMirrored = true
            connection.videoOrientation = .portrait
        }
        didConfigure = true
    }

    private func setPermissionState(_ state: CameraPermissionState) {
        DispatchQueue.main.async { [weak self] in
            self?.permissionState.wrappedValue = state
        }
    }

    private func applyBeauty(to input: CIImage) -> CIImage {
        guard config.isEnabled else { return input }
        let smoothing = max(0, min(1, config.smoothing))
        let brightness = max(0, min(0.3, config.brightness))
        var output = input
        if smoothing > 0.01 {
            let radius = Double(smoothing) * 8.0 + 1.0
            blurFilter.setValue(output, forKey: kCIInputImageKey)
            blurFilter.setValue(radius, forKey: kCIInputRadiusKey)
            guard let blurred = blurFilter.outputImage else { return input }
            let maskAlpha = max(0.05, min(0.45, Double(smoothing) * 0.5))
            let maskColor = CIColor(red: 1, green: 1, blue: 1, alpha: CGFloat(maskAlpha))
            let mask = CIImage(color: maskColor).cropped(to: output.extent)
            blendFilter.setValue(blurred, forKey: kCIInputImageKey)
            blendFilter.setValue(output, forKey: kCIInputBackgroundImageKey)
            blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)
            if let blended = blendFilter.outputImage { output = blended }
        }
        if brightness > 0.01 {
            colorFilter.setValue(output, forKey: kCIInputImageKey)
            colorFilter.setValue(brightness, forKey: kCIInputBrightnessKey)
            colorFilter.setValue(1.0 + brightness * 0.3, forKey: kCIInputSaturationKey)
            colorFilter.setValue(1.0 + brightness * 0.05, forKey: kCIInputContrastKey)
            if let colorAdjusted = colorFilter.outputImage { output = colorAdjusted }
        }
        return output
    }

    @objc private func handleWillResignActive() { stopSession() }
    @objc private func handleDidBecomeActive() {
        guard !isInvalidated else { return }
        requestAndStart()
    }
}

extension BeautyCameraCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !isInvalidated, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // 旋转到竖屏方向（AVCaptureVideoDataOutput 传出的像素是横向的）
        let rawImage = CIImage(cvPixelBuffer: pixelBuffer)
        latestCIImage = rawImage.oriented(.right)
        DispatchQueue.main.async { [weak self] in
            self?.mtkView?.setNeedsDisplay()
        }
    }
}

extension BeautyCameraCoordinator: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard !isInvalidated, let inputImage = latestCIImage, let drawable = view.currentDrawable else { return }
        let processed = applyBeauty(to: inputImage)
        let bounds = CGRect(origin: .zero, size: view.drawableSize)
        let s = min(bounds.width / processed.extent.width, bounds.height / processed.extent.height)
        let scaled = processed.transformed(by: CGAffineTransform(scaleX: s, y: s))
        let ox = (bounds.width - scaled.extent.width) / 2
        let oy = (bounds.height - scaled.extent.height) / 2
        guard let cb = commandQueue.makeCommandBuffer() else { return }
        ciContext.render(scaled, to: drawable.texture, commandBuffer: cb,
            bounds: CGRect(x: ox, y: oy, width: scaled.extent.width, height: scaled.extent.height),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        cb.present(drawable)
        cb.commit()
    }
}
