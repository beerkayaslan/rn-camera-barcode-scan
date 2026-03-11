import ExpoModulesCore
import AVFoundation
import UIKit

class RnCameraBarcodeScanView: ExpoView, AVCaptureMetadataOutputObjectsDelegate {
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isRunning = false
    private var lastScannedValue: String = ""
    private var lastScannedTime: TimeInterval = 0
    private let scanCooldown: TimeInterval = 0.5
    private var metadataOutput: AVCaptureMetadataOutput?
    private var requestedBarcodeTypes: [String]? = nil
    private var torchEnabled: Bool = false
    private var showBoundingBox: Bool = true
    private var isActive: Bool = true
    private var scanDelayMs: Int = 0
    private var enableTapToFocus: Bool = true
    private var enablePinchToZoom: Bool = true
    private var currentZoomFactor: CGFloat = 1.0
    private var initialPinchZoom: CGFloat = 1.0
    private var cornerLayers: [CAShapeLayer] = []
    private var clearTimer: Timer?
    private var isSettingUp = false
    private var focusIndicatorLayer: CAShapeLayer?
    private var focusFadeTimer: Timer?
    
    // High-priority serial queue for metadata processing – keeps main thread free
    private let metadataQueue = DispatchQueue(label: "expo.modules.camerascan.metadata", qos: .userInteractive)
    // Atomic lock for scan cooldown (accessed from metadataQueue)
    private let scanLock = NSLock()
    
    let onBarcodeScan = EventDispatcher()
    
    // All supported barcode types for maximum compatibility
    private var allSupportedBarcodeTypes: [AVMetadataObject.ObjectType] {
        var types: [AVMetadataObject.ObjectType] = [
            .qr,
            .ean8,
            .ean13,
            .pdf417,
            .aztec,
            .code128,
            .code39,
            .code39Mod43,
            .code93,
            .dataMatrix,
            .interleaved2of5,
            .itf14,
            .upce
        ]
        if #available(iOS 15.4, *) {
            types.append(contentsOf: [
                .codabar,
                .gs1DataBar,
                .gs1DataBarExpanded,
                .gs1DataBarLimited,
                .microPDF417,
                .microQR
            ])
        }
        return types
    }
    
    required init(appContext: AppContext? = nil) {
        super.init(appContext: appContext)
        clipsToBounds = true
        isUserInteractionEnabled = true
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapToFocus(_:)))
        addGestureRecognizer(tapGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchToZoom(_:)))
        addGestureRecognizer(pinchGesture)
        
        // Pause/resume camera when app goes to background/foreground
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        // Re-focus when subject area changes (e.g. user moves to a new barcode)
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - App Lifecycle
    
    @objc private func appDidEnterBackground() {
        pauseCamera()
    }
    
    @objc private func appWillEnterForeground() {
        guard isActive else { return }
        resumeCamera()
    }
    
    @objc private func subjectAreaDidChange() {
        // Re-trigger continuous autofocus when the scene changes
        guard let device = (captureSession?.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {}
    }
    
    // MARK: - Tap to Focus
    
    func setEnableTapToFocus(_ enabled: Bool) {
        enableTapToFocus = enabled
    }
    
    @objc private func handleTapToFocus(_ gesture: UITapGestureRecognizer) {
        guard enableTapToFocus else { return }
        guard let previewLayer = previewLayer else { return }
        guard let device = (captureSession?.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        
        let touchPoint = gesture.location(in: self)
        let focusPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: touchPoint)
        
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = focusPoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            // Focus not available
        }
        
        showFocusIndicator(at: touchPoint)
    }
    
    private func showFocusIndicator(at point: CGPoint) {
        focusFadeTimer?.invalidate()
        focusIndicatorLayer?.removeFromSuperlayer()
        
        let size: CGFloat = 70
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        
        let indicator = CAShapeLayer()
        indicator.path = UIBezierPath(roundedRect: rect, cornerRadius: 4).cgPath
        indicator.strokeColor = UIColor.yellow.cgColor
        indicator.fillColor = UIColor.clear.cgColor
        indicator.lineWidth = 2.0
        indicator.opacity = 1.0
        layer.addSublayer(indicator)
        focusIndicatorLayer = indicator
        
        // Animate scale
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 1.3
        scaleAnimation.toValue = 1.0
        scaleAnimation.duration = 0.2
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        indicator.add(scaleAnimation, forKey: "scale")
        
        // Fade out after 1 second
        focusFadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1.0
            fadeOut.toValue = 0.0
            fadeOut.duration = 0.3
            fadeOut.isRemovedOnCompletion = false
            fadeOut.fillMode = .forwards
            indicator.add(fadeOut, forKey: "fadeOut")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.focusIndicatorLayer?.removeFromSuperlayer()
                self?.focusIndicatorLayer = nil
            }
        }
    }
    
    // MARK: - Pinch to Zoom
    
    func setEnablePinchToZoom(_ enabled: Bool) {
        enablePinchToZoom = enabled
    }
    
    @objc private func handlePinchToZoom(_ gesture: UIPinchGestureRecognizer) {
        guard enablePinchToZoom else { return }
        guard let device = (captureSession?.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        
        switch gesture.state {
        case .began:
            initialPinchZoom = currentZoomFactor
        case .changed:
            let newZoom = initialPinchZoom * gesture.scale
            let clampedZoom = max(1.0, min(newZoom, device.activeFormat.videoMaxZoomFactor, 10.0))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clampedZoom
                device.unlockForConfiguration()
                currentZoomFactor = clampedZoom
            } catch {
                // Zoom not available
            }
        default:
            break
        }
    }
    
    func setIsActive(_ active: Bool) {
        isActive = active
        if active {
            resumeCamera()
        } else {
            pauseCamera()
        }
    }
    
    private func resumeCamera() {
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = true
            }
        }
    }
    
    private func pauseCamera() {
        clearBoundingBoxes()
        guard let session = captureSession, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = false
            }
        }
    }
    
    func setShowBoundingBox(_ show: Bool) {
        showBoundingBox = show
        if !show {
            clearBoundingBoxes()
        }
    }
    
    func setTorch(_ enabled: Bool) {
        torchEnabled = enabled
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = enabled ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Torch not available
        }
    }
    
    func setScanDelay(_ delay: Int) {
        scanDelayMs = delay
    }
    
    func setBarcodeTypes(_ types: [String]?) {
        guard types != requestedBarcodeTypes else { return }
        requestedBarcodeTypes = types
        // Update metadata output if camera is already running
        if let output = metadataOutput {
            let available = output.availableMetadataObjectTypes
            let desired = resolveDesiredTypes()
            output.metadataObjectTypes = desired.filter { available.contains($0) }
        }
    }
    
    private func resolveDesiredTypes() -> [AVMetadataObject.ObjectType] {
        guard let types = requestedBarcodeTypes, !types.isEmpty else {
            return allSupportedBarcodeTypes
        }
        return types.compactMap { mapBarcodeTypeName($0) }
    }
    
    private func mapBarcodeTypeName(_ name: String) -> AVMetadataObject.ObjectType? {
        switch name {
        case "QR_CODE": return .qr
        case "EAN_8": return .ean8
        case "EAN_13": return .ean13
        case "CODE_128": return .code128
        case "CODE_39": return .code39
        case "CODE_39_MOD_43": return .code39Mod43
        case "CODE_93": return .code93
        case "DATA_MATRIX": return .dataMatrix
        case "PDF417": return .pdf417
        case "AZTEC": return .aztec
        case "UPC_E": return .upce
        case "ITF_14": return .itf14
        case "INTERLEAVED_2_OF_5": return .interleaved2of5
        case "CODABAR":
            if #available(iOS 15.4, *) { return .codabar }
            return nil
        case "GS1_DATABAR":
            if #available(iOS 15.4, *) { return .gs1DataBar }
            return nil
        case "GS1_DATABAR_EXPANDED":
            if #available(iOS 15.4, *) { return .gs1DataBarExpanded }
            return nil
        case "GS1_DATABAR_LIMITED":
            if #available(iOS 15.4, *) { return .gs1DataBarLimited }
            return nil
        case "MICRO_PDF417":
            if #available(iOS 15.4, *) { return .microPDF417 }
            return nil
        case "MICRO_QR":
            if #available(iOS 15.4, *) { return .microQR }
            return nil
        default: return nil
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        
        // Update rectOfInterest when layout changes
        if let output = metadataOutput, let preview = previewLayer, bounds.width > 0, bounds.height > 0 {
            output.rectOfInterest = preview.metadataOutputRectConverted(fromLayerRect: preview.bounds)
        }
        
        if !isRunning && !isSettingUp {
            setupCamera()
        }
    }
    
    private func setupCamera() {
        guard isActive, !isSettingUp else { return }
        isSettingUp = true
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            isSettingUp = false
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCamera()
                    }
                }
            }
            return
        }
        
        let session = AVCaptureSession()
        // Batch all configuration changes for atomic commit
        session.beginConfiguration()
        
        // 1280x720 is more than enough for barcode detection and processes much faster than .high
        session.sessionPreset = .hd1280x720
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            isSettingUp = false
            return
        }
        
        // Optimize camera hardware for barcode scanning
        do {
            try videoDevice.lockForConfiguration()
            
            // --- Focus ---
            // Continuous auto-focus keeps re-evaluating focus
            if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoDevice.focusMode = .continuousAutoFocus
            }
            // Restrict AF range to near for faster close-up focus lock
            if videoDevice.isAutoFocusRangeRestrictionSupported {
                videoDevice.autoFocusRangeRestriction = .near
            }
            // Focus at center where barcodes typically are
            if videoDevice.isFocusPointOfInterestSupported {
                videoDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            // Smooth auto-focus for video gives more stable results
            if videoDevice.isSmoothAutoFocusSupported {
                videoDevice.isSmoothAutoFocusEnabled = true
            }
            
            // --- Exposure ---
            // Center exposure metering for barcode area
            if videoDevice.isExposurePointOfInterestSupported {
                videoDevice.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoDevice.exposureMode = .continuousAutoExposure
            }
            
            // --- Low-light boost ---
            // Automatically brightens in dim environments
            if videoDevice.isLowLightBoostSupported {
                videoDevice.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            
            // --- Disable Video HDR --- reduces processing overhead
            if videoDevice.activeFormat.isVideoHDRSupported {
                videoDevice.automaticallyAdjustsVideoHDREnabled = false
                videoDevice.isVideoHDREnabled = false
            }
            
            // --- Subject area change monitoring ---
            // Notifies when scene changes so we can re-trigger AF
            videoDevice.isSubjectAreaChangeMonitoringEnabled = true
            
            // --- Frame rate cap at 30fps ---
            // Faster frame processing per-frame, avoids wasting GPU on 60fps
            videoDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            videoDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
            
            videoDevice.unlockForConfiguration()
        } catch {
            // Continue without optimization
        }
        
        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            session.commitConfiguration()
            isSettingUp = false
            return
        }
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            // Use a dedicated high-priority queue instead of main thread
            metadataOutput.setMetadataObjectsDelegate(self, queue: metadataQueue)
            
            // Filter to only types actually supported by the device
            let available = metadataOutput.availableMetadataObjectTypes
            let desiredTypes = resolveDesiredTypes()
            let typesToUse = desiredTypes.filter { available.contains($0) }
            metadataOutput.metadataObjectTypes = typesToUse
            self.metadataOutput = metadataOutput
        }
        
        // Commit all config changes at once
        session.commitConfiguration()
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = bounds
        layer.insertSublayer(previewLayer, at: 0)
        
        self.captureSession = session
        self.previewLayer = previewLayer
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.startRunning()
            DispatchQueue.main.async {
                guard let strongSelf = self else { return }
                strongSelf.isRunning = true
                strongSelf.isSettingUp = false
                // Restrict barcode scanning to visible area only
                if let preview = strongSelf.previewLayer, strongSelf.bounds.width > 0, strongSelf.bounds.height > 0 {
                    metadataOutput.rectOfInterest = preview.metadataOutputRectConverted(fromLayerRect: preview.bounds)
                }
            }
        }
    }
    
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        // This callback is on metadataQueue – keep it fast
        guard !metadataObjects.isEmpty else { return }
        
        // Pick the best barcode: prefer the one closest to center of frame
        let bestObject = pickBestBarcode(from: metadataObjects)
        guard let readableObject = bestObject as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue else {
            return
        }
        
        // Thread-safe cooldown check
        let now = Date().timeIntervalSince1970
        let effectiveCooldown = scanDelayMs > 0 ? Double(scanDelayMs) / 1000.0 : scanCooldown
        scanLock.lock()
        var shouldSkip = false
        if now - lastScannedTime < effectiveCooldown {
            if scanDelayMs > 0 || stringValue == lastScannedValue {
                shouldSkip = true
            }
        }
        if !shouldSkip {
            lastScannedValue = stringValue
            lastScannedTime = now
        }
        scanLock.unlock()
        
        if shouldSkip { return }
        
        let typeName = getBarcodeTypeName(readableObject.type)
        let rawFormat = readableObject.type.rawValue
        
        // Dispatch UI work and event back to main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Draw bounding box only for successfully decoded barcodes
            if self.showBoundingBox {
                self.drawBoundingBoxes([bestObject])
            }
            
            self.onBarcodeScan([
                "data": stringValue,
                "type": typeName,
                "format": rawFormat
            ])
        }
    }
    
    /// From multiple detected barcodes, pick the one closest to the center of the frame.
    /// This avoids accidentally reporting a barcode at the edge when the user is aiming at center.
    private func pickBestBarcode(from metadataObjects: [AVMetadataObject]) -> AVMetadataObject {
        guard metadataObjects.count > 1 else { return metadataObjects[0] }
        
        // Center of normalized coordinate space is (0.5, 0.5)
        let center = CGPoint(x: 0.5, y: 0.5)
        var bestObject = metadataObjects[0]
        var bestDistance = CGFloat.greatestFiniteMagnitude
        
        for obj in metadataObjects {
            guard (obj as? AVMetadataMachineReadableCodeObject)?.stringValue != nil else { continue }
            let objCenter = CGPoint(x: obj.bounds.midX, y: obj.bounds.midY)
            let dx = objCenter.x - center.x
            let dy = objCenter.y - center.y
            let dist = dx * dx + dy * dy
            if dist < bestDistance {
                bestDistance = dist
                bestObject = obj
            }
        }
        return bestObject
    }
    
    func stopCamera() {
        clearTimer?.invalidate()
        clearTimer = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
    }
    
    override func removeFromSuperview() {
        NotificationCenter.default.removeObserver(self)
        stopCamera()
        clearBoundingBoxes()
        focusFadeTimer?.invalidate()
        focusIndicatorLayer?.removeFromSuperlayer()
        previewLayer?.removeFromSuperlayer()
        super.removeFromSuperview()
    }
    
    // MARK: - Bounding Box Drawing
    
    private func drawBoundingBoxes(_ metadataObjects: [AVMetadataObject]) {
        clearBoundingBoxes()
        
        guard let previewLayer = previewLayer else { return }
        
        for metadata in metadataObjects {
            guard let transformed = previewLayer.transformedMetadataObject(for: metadata) else { continue }
            let rect = transformed.bounds.insetBy(dx: -4, dy: -4)
            
            // Main bounding box
            let boxLayer = CAShapeLayer()
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            boxLayer.path = path.cgPath
            boxLayer.strokeColor = UIColor(red: 0.298, green: 0.686, blue: 0.314, alpha: 1.0).cgColor
            boxLayer.fillColor = UIColor(red: 0.298, green: 0.686, blue: 0.314, alpha: 0.08).cgColor
            boxLayer.lineWidth = 3.0
            layer.addSublayer(boxLayer)
            cornerLayers.append(boxLayer)
            
            // Corner accents
            let cornerLen = min(rect.width, rect.height) * 0.2
            let corners = createCornerPath(rect: rect, cornerLength: cornerLen)
            let cornerLayer = CAShapeLayer()
            cornerLayer.path = corners.cgPath
            cornerLayer.strokeColor = UIColor(red: 0.298, green: 0.686, blue: 0.314, alpha: 1.0).cgColor
            cornerLayer.fillColor = UIColor.clear.cgColor
            cornerLayer.lineWidth = 5.0
            cornerLayer.lineCap = .round
            layer.addSublayer(cornerLayer)
            cornerLayers.append(cornerLayer)
        }
        
        // Auto-clear after 500ms
        clearTimer?.invalidate()
        clearTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.clearBoundingBoxes()
        }
    }
    
    private func clearBoundingBoxes() {
        for layer in cornerLayers {
            layer.removeFromSuperlayer()
        }
        cornerLayers.removeAll()
    }
    
    private func createCornerPath(rect: CGRect, cornerLength: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        // Top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
        // Top-right
        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
        // Bottom-left
        path.move(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
        return path
    }
    
    private func getBarcodeTypeName(_ type: AVMetadataObject.ObjectType) -> String {
        switch type {
        case .qr: return "QR_CODE"
        case .ean8: return "EAN_8"
        case .ean13: return "EAN_13"
        case .pdf417: return "PDF417"
        case .aztec: return "AZTEC"
        case .code128: return "CODE_128"
        case .code39: return "CODE_39"
        case .code39Mod43: return "CODE_39_MOD_43"
        case .code93: return "CODE_93"
        case .dataMatrix: return "DATA_MATRIX"
        case .interleaved2of5: return "INTERLEAVED_2_OF_5"
        case .itf14: return "ITF_14"
        case .upce: return "UPC_E"
        default:
            if #available(iOS 15.4, *) {
                switch type {
                case .codabar: return "CODABAR"
                case .gs1DataBar: return "GS1_DATABAR"
                case .gs1DataBarExpanded: return "GS1_DATABAR_EXPANDED"
                case .gs1DataBarLimited: return "GS1_DATABAR_LIMITED"
                case .microPDF417: return "MICRO_PDF417"
                case .microQR: return "MICRO_QR"
                default: return "UNKNOWN"
                }
            }
            return "UNKNOWN"
        }
    }
}
