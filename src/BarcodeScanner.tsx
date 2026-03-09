import React from "react";
import { StyleSheet } from "react-native";
import NativeView from "./RnCameraBarcodeScanView";
import type { BarcodeScannerProps, BarcodeScanResult } from "./types";

/**
 * BarcodeScanner — A camera-based barcode scanner component.
 *
 * Supports all major barcode formats (QR, EAN, Code128, UPC, etc.)
 * on both Android (ML Kit) and iOS (AVFoundation).
 *
 * @example
 * ```tsx
 * <BarcodeScanner
 *   style={{ width: 300, height: 400 }}
 *   onBarcodeScan={(result) => {
 *     console.log(result.data, result.type);
 *   }}
 * />
 * ```
 */
export function BarcodeScanner({
  onBarcodeScan,
  barcodeTypes,
  torch = false,
  showBoundingBox = true,
  isActive = true,
  scanDelay = 0,
  enableTapToFocus = true,
  enablePinchToZoom = true,
  style,
}: BarcodeScannerProps) {
  const handleBarcodeScan = React.useCallback(
    (event: {
      nativeEvent: { data: string; type: string; format: number | string };
    }) => {
      onBarcodeScan?.(event.nativeEvent as BarcodeScanResult);
    },
    [onBarcodeScan],
  );

  return (
    <NativeView
      style={[styles.default, style]}
      onBarcodeScan={handleBarcodeScan}
      barcodeTypes={barcodeTypes}
      torch={torch}
      showBoundingBox={showBoundingBox}
      isActive={isActive}
      scanDelay={scanDelay}
      enableTapToFocus={enableTapToFocus}
      enablePinchToZoom={enablePinchToZoom}
    />
  );
}

const styles = StyleSheet.create({
  default: {
    width: "100%",
    height: 300,
    overflow: "hidden",
    backgroundColor: "#000",
  },
});
