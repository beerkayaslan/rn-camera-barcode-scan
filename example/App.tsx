import { useState, useEffect } from "react";
import { StyleSheet, Text, View, Alert, Platform } from "react-native";
import {
  BarcodeScanner,
  requestCameraPermission,
  getCameraPermissionStatus,
} from "rn-camera-barcode-scan";
import type { BarcodeScanResult } from "rn-camera-barcode-scan";

export default function App() {
  const [hasPermission, setHasPermission] = useState(false);
  const [scannedData, setScannedData] = useState<BarcodeScanResult | null>(
    null,
  );

  useEffect(() => {
    (async () => {
      const status = getCameraPermissionStatus();
      if (status === "granted") {
        setHasPermission(true);
      } else {
        const result = await requestCameraPermission();
        setHasPermission(result === "granted");
      }
    })();
  }, []);

  const handleBarcodeScan = (result: BarcodeScanResult) => {
    setScannedData(result);
    // You can also show an alert
    // Alert.alert("Barcode Scanned", `Type: ${result.type}\nData: ${result.data}`);
  };

  if (!hasPermission) {
    return (
      <View style={styles.container}>
        <Text style={styles.message}>
          Camera permission is required to scan barcodes.
        </Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Barcode Scanner</Text>

      {/* You can customize the size with width/height */}
      {/* Pass barcodeTypes to scan only specific types, omit to scan all */}
      <BarcodeScanner
        style={styles.scanner}
        barcodeTypes={["QR_CODE", "EAN_13", "CODE_128"]}
        onBarcodeScan={handleBarcodeScan}
      />

      {scannedData && (
        <View style={styles.resultContainer}>
          <Text style={styles.resultLabel}>Scanned Result:</Text>
          <Text style={styles.resultType}>Type: {scannedData.type}</Text>
          <Text style={styles.resultData}>{scannedData.data}</Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#f5f5f5",
    alignItems: "center",
    justifyContent: "center",
    padding: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: "bold",
    marginBottom: 20,
    color: "#333",
  },
  message: {
    fontSize: 16,
    color: "#666",
    textAlign: "center",
  },
  scanner: {
    width: 320,
    height: 400,
    borderRadius: 12,
    overflow: "hidden",
  },
  resultContainer: {
    marginTop: 20,
    padding: 16,
    backgroundColor: "#fff",
    borderRadius: 12,
    width: "100%",
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  resultLabel: {
    fontSize: 14,
    color: "#999",
    marginBottom: 4,
  },
  resultType: {
    fontSize: 14,
    color: "#666",
    marginBottom: 4,
  },
  resultData: {
    fontSize: 18,
    fontWeight: "600",
    color: "#333",
  },
});
