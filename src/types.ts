export type BarcodeType =
  | "QR_CODE"
  | "EAN_8"
  | "EAN_13"
  | "CODE_128"
  | "CODE_39"
  | "CODE_39_MOD_43"
  | "CODE_93"
  | "CODABAR"
  | "DATA_MATRIX"
  | "PDF417"
  | "AZTEC"
  | "UPC_A"
  | "UPC_E"
  | "ITF"
  | "ITF_14"
  | "INTERLEAVED_2_OF_5"
  | "GS1_DATABAR"
  | "GS1_DATABAR_EXPANDED"
  | "GS1_DATABAR_LIMITED"
  | "MICRO_PDF417"
  | "MICRO_QR"
  | "UNKNOWN";

export type BarcodeScanResult = {
  /** The scanned barcode data/value */
  data: string;
  /** The barcode type name */
  type: BarcodeType;
  /** The raw format code from the native scanner */
  format: number | string;
};

export type BarcodeScannerProps = {
  /** Callback fired when a barcode is successfully scanned */
  onBarcodeScan: (result: BarcodeScanResult) => void;
  /**
   * Which barcode types to scan. If omitted or empty, ALL types are scanned.
   * @example ['QR_CODE', 'EAN_13', 'CODE_128']
   */
  barcodeTypes?: BarcodeType[];
  /** Enable or disable the camera torch/flash. Default: false */
  torch?: boolean;
  /** Show a green bounding box around detected barcodes. Default: true */
  showBoundingBox?: boolean;
  /** Activate or deactivate the camera. When false, the camera stops without unmounting the view. Default: true */
  isActive?: boolean;
  /** Delay in milliseconds before the scanner can scan again after a successful read. 0 means continuous scanning. Default: 0 */
  scanDelay?: number;
  /** Enable tap-to-focus: tap anywhere on the camera view to focus on that point. Default: true */
  enableTapToFocus?: boolean;
  /** Enable pinch-to-zoom: use two fingers to zoom in/out on the camera view. Default: true */
  enablePinchToZoom?: boolean;
  /** Style for the scanner view — use width/height to control size */
  style?: import("react-native").StyleProp<import("react-native").ViewStyle>;
};

export type CameraPermissionStatus =
  | "granted"
  | "denied"
  | "not-determined"
  | "restricted"
  | "unavailable"
  | "unknown";
