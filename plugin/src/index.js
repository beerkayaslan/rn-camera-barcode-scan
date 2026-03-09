const {
  withInfoPlist,
  withAndroidManifest,
  AndroidConfig,
} = require("expo/config-plugins");

const withCameraBarcodeScan = (config, props = {}) => {
  const cameraPermissionText =
    props.cameraPermissionText || "This app uses the camera to scan barcodes.";

  // iOS: Add NSCameraUsageDescription to Info.plist
  config = withInfoPlist(config, (config) => {
    config.modResults.NSCameraUsageDescription = cameraPermissionText;
    return config;
  });

  // Android: Ensure CAMERA permission is in AndroidManifest
  config = withAndroidManifest(config, (config) => {
    const mainApplication = AndroidConfig.Manifest.getMainApplicationOrThrow(
      config.modResults
    );

    // Camera permission is already in our module's AndroidManifest.xml
    // but we add it here too for explicitness
    AndroidConfig.Permissions.ensurePermission(
      config.modResults,
      "android.permission.CAMERA"
    );

    return config;
  });

  return config;
};

module.exports = withCameraBarcodeScan;
