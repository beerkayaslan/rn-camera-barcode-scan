import RnCameraBarcodeScanModule from "./RnCameraBarcodeScanModule";
import type { CameraPermissionStatus } from "./types";

export { BarcodeScanner } from "./BarcodeScanner";

export type {
  BarcodeScanResult,
  BarcodeScannerProps,
  BarcodeType,
  CameraPermissionStatus,
} from "./types";

/**
 * Check current camera permission status (sync, does not prompt user).
 */
export function getCameraPermissionStatus(): CameraPermissionStatus {
  return RnCameraBarcodeScanModule.requestCameraPermission();
}

/**
 * Request camera permission from the user (async, shows system dialog).
 */
export async function requestCameraPermission(): Promise<CameraPermissionStatus> {
  return RnCameraBarcodeScanModule.requestCameraPermissionAsync();
}
