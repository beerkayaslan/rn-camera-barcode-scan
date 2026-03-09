import { requireNativeViewManager } from "expo-modules-core";
import { ViewProps } from "react-native";
import type { BarcodeScanResult } from "./types";

export type BarcodeScanEvent = {
  nativeEvent: BarcodeScanResult;
};

export type RnCameraBarcodeScanViewProps = ViewProps & {
  onBarcodeScan?: (event: BarcodeScanEvent) => void;
  barcodeTypes?: string[];
  torch?: boolean;
  showBoundingBox?: boolean;
  isActive?: boolean;
  scanDelay?: number;
  enableTapToFocus?: boolean;
  enablePinchToZoom?: boolean;
};

const NativeView = requireNativeViewManager<RnCameraBarcodeScanViewProps>(
  "RnCameraBarcodeScan",
);

export default NativeView;
