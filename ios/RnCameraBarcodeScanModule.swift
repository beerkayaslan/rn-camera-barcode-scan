import ExpoModulesCore
import AVFoundation

public class RnCameraBarcodeScanModule: Module {
    public func definition() -> ModuleDefinition {
        Name("RnCameraBarcodeScan")
        
        Events("onBarcodeScan")
        
        View(RnCameraBarcodeScanView.self) {
            Events("onBarcodeScan")
            
            Prop("barcodeTypes") { (view: RnCameraBarcodeScanView, types: [String]?) in
                view.setBarcodeTypes(types)
            }
            
            Prop("torch") { (view: RnCameraBarcodeScanView, enabled: Bool) in
                view.setTorch(enabled)
            }
            
            Prop("showBoundingBox") { (view: RnCameraBarcodeScanView, show: Bool) in
                view.setShowBoundingBox(show)
            }
            
            Prop("isActive") { (view: RnCameraBarcodeScanView, active: Bool) in
                view.setIsActive(active)
            }
            
            Prop("scanDelay") { (view: RnCameraBarcodeScanView, delay: Int) in
                view.setScanDelay(delay)
            }
            
            Prop("enableTapToFocus") { (view: RnCameraBarcodeScanView, enabled: Bool) in
                view.setEnableTapToFocus(enabled)
            }
            
            Prop("enablePinchToZoom") { (view: RnCameraBarcodeScanView, enabled: Bool) in
                view.setEnablePinchToZoom(enabled)
            }
        }
        
        Function("requestCameraPermission") { () -> String in
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            switch status {
            case .authorized:
                return "granted"
            case .notDetermined:
                return "not-determined"
            case .denied:
                return "denied"
            case .restricted:
                return "restricted"
            @unknown default:
                return "unknown"
            }
        }
        
        AsyncFunction("requestCameraPermissionAsync") { (promise: Promise) in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                promise.resolve(granted ? "granted" : "denied")
            }
        }
    }
}
