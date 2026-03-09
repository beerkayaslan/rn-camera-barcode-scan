package expo.modules.camerascan

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.Promise

class RnCameraBarcodeScanModule : Module() {
    override fun definition() = ModuleDefinition {

        Name("RnCameraBarcodeScan")

        Events("onBarcodeScan")

        View(RnCameraBarcodeScanView::class) {
            Events("onBarcodeScan")

            Prop("barcodeTypes") { view: RnCameraBarcodeScanView, types: List<String>? ->
                view.setBarcodeTypes(types)
            }

            Prop("torch") { view: RnCameraBarcodeScanView, enabled: Boolean ->
                view.setTorch(enabled)
            }

            Prop("showBoundingBox") { view: RnCameraBarcodeScanView, show: Boolean ->
                view.setShowBoundingBox(show)
            }

            Prop("isActive") { view: RnCameraBarcodeScanView, active: Boolean ->
                view.setIsActive(active)
            }

            Prop("scanDelay") { view: RnCameraBarcodeScanView, delay: Int ->
                view.setScanDelay(delay.toLong())
            }

            Prop("enableTapToFocus") { view: RnCameraBarcodeScanView, enabled: Boolean ->
                view.setEnableTapToFocus(enabled)
            }

            Prop("enablePinchToZoom") { view: RnCameraBarcodeScanView, enabled: Boolean ->
                view.setEnablePinchToZoom(enabled)
            }
        }

        // Sync: check current status
        Function("requestCameraPermission") {
            val ctx = appContext.reactContext ?: return@Function "unknown"
            val result = ContextCompat.checkSelfPermission(ctx, Manifest.permission.CAMERA)
            if (result == PackageManager.PERMISSION_GRANTED) "granted" else "denied"
        }

        // Async: request permission dialog
        AsyncFunction("requestCameraPermissionAsync") { promise: Promise ->
            val ctx = appContext.reactContext ?: run {
                promise.resolve("denied")
                return@AsyncFunction
            }

            val currentPermission = ContextCompat.checkSelfPermission(ctx, Manifest.permission.CAMERA)
            if (currentPermission == PackageManager.PERMISSION_GRANTED) {
                promise.resolve("granted")
                return@AsyncFunction
            }

            val permissions = appContext.permissions ?: run {
                promise.resolve("denied")
                return@AsyncFunction
            }

            permissions.askForPermissions(
                { permissionResponse ->
                    val granted = ContextCompat.checkSelfPermission(ctx, Manifest.permission.CAMERA) ==
                        PackageManager.PERMISSION_GRANTED
                    promise.resolve(if (granted) "granted" else "denied")
                },
                Manifest.permission.CAMERA
            )
        }
    }
}
