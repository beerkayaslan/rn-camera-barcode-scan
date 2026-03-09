# rn-camera-barcode-scan

![WhatsApp Video 2026-03-09 at 16 37 49](https://github.com/user-attachments/assets/96a6b0f2-4413-4f99-8bb4-e64ccfac5038)

A high-performance, real-time barcode scanner component for React Native (Expo). Supports 15+ barcode formats on both Android and iOS with native performance.

- **Android** — CameraX + Google ML Kit (on-device, no internet required)
- **iOS** — AVFoundation native barcode engine

## Features

- 15+ barcode formats (QR, EAN, Code 128, Data Matrix, and more)
- Real-time green bounding box overlay on decoded barcodes
- Torch / flash control
- Pause & resume camera without unmounting (`isActive`)
- Close-range autofocus optimization (periodic AF on Android, near-range restriction on iOS)
- Scans only within the visible view area — not the full sensor
- Expo Config Plugin for automatic permission setup
- Works with both Old Architecture (Bridge) and New Architecture (Fabric + TurboModules)

## Installation


```bash
npx expo install rn-camera-barcode-scan
```

or

```bash
npm install rn-camera-barcode-scan
```

### Expo Config Plugin

Add to your `app.json` or `app.config.js`:

```json
{
  "expo": {
    "plugins": [
      [
        "rn-camera-barcode-scan",
        {
          "cameraPermissionText": "This app uses the camera to scan barcodes."
        }
      ]
    ]
  }
}
```

Then rebuild:

```bash
npx expo prebuild
```

## Quick Start

```tsx
import { BarcodeScanner, requestCameraPermission } from "rn-camera-barcode-scan";

export default function App() {
  const [hasPermission, setHasPermission] = useState(false);

  useEffect(() => {
    requestCameraPermission().then((status) => {
      setHasPermission(status === "granted");
    });
  }, []);

  if (!hasPermission) return <Text>Camera permission required</Text>;

  return (
    <BarcodeScanner
      style={{ width: 320, height: 400, borderRadius: 12 }}
      onBarcodeScan={(result) => {
        console.log(result.type, result.data);
      }}
    />
  );
}
```

## Supported Barcode Formats

| Format | Android | iOS | Type String |
|--------|:-------:|:---:|-------------|
| QR Code | ✅ | ✅ | `QR_CODE` |
| EAN-8 | ✅ | ✅ | `EAN_8` |
| EAN-13 | ✅ | ✅ | `EAN_13` |
| Code 128 | ✅ | ✅ | `CODE_128` |
| Code 39 | ✅ | ✅ | `CODE_39` |
| Code 93 | ✅ | ✅ | `CODE_93` |
| Codabar | ✅ | ✅ | `CODABAR` |
| UPC-A | ✅ | — | `UPC_A` |
| UPC-E | ✅ | ✅ | `UPC_E` |
| ITF | ✅ | ✅ | `ITF` |
| Data Matrix | ✅ | ✅ | `DATA_MATRIX` |
| PDF417 | ✅ | ✅ | `PDF417` |
| Aztec | ✅ | ✅ | `AZTEC` |
| Micro QR | — | ✅ | `MICRO_QR` |
| GS1 DataBar | — | ✅ | `GS1_DATABAR` |

> iOS-only formats require iOS 15.4+.

## API

### `<BarcodeScanner />`

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `onBarcodeScan` | `(result: BarcodeScanResult) => void` | *required* | Called when a barcode is successfully decoded |
| `barcodeTypes` | `BarcodeType[]` | All formats | Restrict scanning to specific barcode types |
| `torch` | `boolean` | `false` | Enable/disable camera flashlight |
| `showBoundingBox` | `boolean` | `true` | Show green overlay around decoded barcodes |
| `isActive` | `boolean` | `true` | Start/stop camera without unmounting the view |
| `scanDelay` | `number` | `0` | Delay in ms before the scanner can scan again after a successful read. 0 = continuous |
| `style` | `ViewStyle` | — | View style (width, height, borderRadius, etc.) |

### `BarcodeScanResult`

```ts
{
  data: string;            // The barcode content
  type: BarcodeType;       // e.g. "QR_CODE", "EAN_13", "CODE_128"
  format: number | string; // Raw native format code
}
```

### Permission Functions

```ts
import { getCameraPermissionStatus, requestCameraPermission } from "rn-camera-barcode-scan";

// Sync — check current status (does not prompt user)
const status = getCameraPermissionStatus();
// → "granted" | "denied" | "not-determined" | "restricted" | "unavailable" | "unknown"

// Async — show system permission dialog
const result = await requestCameraPermission();
// → "granted" | "denied"
```

## Usage Examples

### Filter Barcode Types

```tsx
<BarcodeScanner
  style={{ width: 300, height: 400 }}
  barcodeTypes={["QR_CODE", "EAN_13"]}
  onBarcodeScan={(result) => console.log(result)}
/>
```

### Torch Control

```tsx
const [torch, setTorch] = useState(false);

<BarcodeScanner
  style={{ width: 300, height: 400 }}
  torch={torch}
  onBarcodeScan={(result) => console.log(result)}
/>
<Button title={torch ? "Flash Off" : "Flash On"} onPress={() => setTorch(!torch)} />
```

### Pause After Scan

```tsx
const [active, setActive] = useState(true);

<BarcodeScanner
  style={{ width: 300, height: 400 }}
  isActive={active}
  onBarcodeScan={(result) => {
    setActive(false);
    Alert.alert(result.type, result.data, [
      { text: "Scan Again", onPress: () => setActive(true) },
    ]);
  }}
/>
```

### Disable Bounding Box

```tsx
<BarcodeScanner
  style={{ width: 300, height: 400 }}
  showBoundingBox={false}
  onBarcodeScan={(result) => console.log(result)}
/>
```

### Scan Delay (Debounce)

Prevent rapid repeated scans by adding a delay after each successful read:

```tsx
<BarcodeScanner
  style={{ width: 300, height: 400 }}
  scanDelay={2000} // Wait 2 seconds after each scan
  onBarcodeScan={(result) => console.log(result)}
/>
```

### Full-Screen Scanner

```tsx
<BarcodeScanner
  style={{ flex: 1 }}
  onBarcodeScan={(result) => console.log(result)}
/>
```

## Full Example

```tsx
import { useState, useEffect } from "react";
import { View, Text, Button, StyleSheet, Alert } from "react-native";
import {
  BarcodeScanner,
  requestCameraPermission,
  getCameraPermissionStatus,
} from "rn-camera-barcode-scan";
import type { BarcodeScanResult } from "rn-camera-barcode-scan";

export default function ScannerScreen() {
  const [hasPermission, setHasPermission] = useState(false);
  const [active, setActive] = useState(true);
  const [torch, setTorch] = useState(false);
  const [result, setResult] = useState<BarcodeScanResult | null>(null);

  useEffect(() => {
    (async () => {
      const status = getCameraPermissionStatus();
      if (status === "granted") {
        setHasPermission(true);
      } else {
        const res = await requestCameraPermission();
        setHasPermission(res === "granted");
      }
    })();
  }, []);

  const handleScan = (data: BarcodeScanResult) => {
    setResult(data);
    setActive(false);
    setTimeout(() => setActive(true), 3000);
  };

  if (!hasPermission) {
    return (
      <View style={styles.container}>
        <Text>Camera permission is required to scan barcodes.</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <BarcodeScanner
        style={styles.scanner}
        isActive={active}
        torch={torch}
        showBoundingBox
        barcodeTypes={["QR_CODE", "EAN_13", "EAN_8", "CODE_128"]}
        onBarcodeScan={handleScan}
      />

      <Button
        title={torch ? "Flash Off" : "Flash On"}
        onPress={() => setTorch(!torch)}
      />

      {result && (
        <Text style={styles.result}>
          {result.type}: {result.data}
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, alignItems: "center", justifyContent: "center" },
  scanner: { width: 320, height: 400, borderRadius: 12 },
  result: { marginTop: 20, fontSize: 16 },
});
```

## How It Works

**Android**: Uses CameraX for camera management and Google ML Kit Barcode Scanning API for decoding. ML Kit runs entirely on-device — no internet required. A shared ViewPort + cropRect ensures only barcodes within the visible view area are reported. Periodic center-focus keeps autofocus locked at close range.

**iOS**: Uses AVFoundation's `AVCaptureMetadataOutput` for native barcode detection. `rectOfInterest` restricts scanning to the visible view bounds. Near-range AF restriction and center focus point optimize for close-up scanning.

Both platforms include a 500ms cooldown to prevent the same barcode from firing repeatedly.

## Requirements

| | Version |
|--|---------|
| Expo SDK | ≥ 52 |
| React | ≥ 18 |
| React Native | ≥ 0.76 |
| iOS | ≥ 15.0 |
| Android minSdk | ≥ 24 |

## Architecture

Built with Expo Modules API (Swift + Kotlin). Automatically works with both the **old architecture** (Bridge) and the **new architecture** (Fabric + TurboModules) — no extra configuration needed.

## License

MIT
