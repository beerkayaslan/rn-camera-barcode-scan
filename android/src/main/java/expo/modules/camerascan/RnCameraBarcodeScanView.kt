package expo.modules.camerascan

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.CornerPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import androidx.annotation.OptIn
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.findViewTreeLifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.viewevent.EventDispatcher
import expo.modules.kotlin.views.ExpoView
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class RnCameraBarcodeScanView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {

    companion object {
        private const val TAG = "BarcodeScanner"
        private const val SCAN_COOLDOWN_MS = 500L
        private const val OVERLAY_CLEAR_DELAY_MS = 500L
    }

    // Camera
    private val previewView = PreviewView(context).apply {
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
    }
    private var cameraProvider: ProcessCameraProvider? = null
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var barcodeScanner: BarcodeScanner
    private var camera: androidx.camera.core.Camera? = null
    private var isCameraRunning = false
    private var isCameraStarting = false
    private var isViewAttached = false

    // Overlay
    private val overlayView = OverlayView(context)

    // State
    private var lastScannedValue = ""
    private var lastScannedTime = 0L
    private var requestedBarcodeTypes: List<String>? = null
    private var torchEnabled = false
    private var showBoundingBox = true
    private var isActive = true
    private var scanDelayMs = 0L
    private var enableTapToFocus = true
    private var enablePinchToZoom = true

    // Handlers
    private val mainHandler = Handler(Looper.getMainLooper())
    private var clearOverlayRunnable: Runnable? = null

    // Gesture detectors
    private val scaleGestureDetector = ScaleGestureDetector(context, object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: ScaleGestureDetector): Boolean {
            if (!enablePinchToZoom) return false
            val cam = camera ?: return false
            val zoomState = cam.cameraInfo.zoomState.value ?: return false
            val newZoom = zoomState.zoomRatio * detector.scaleFactor
            val clamped = newZoom.coerceIn(zoomState.minZoomRatio, zoomState.maxZoomRatio)
            cam.cameraControl.setZoomRatio(clamped)
            return true
        }
    })

    val onBarcodeScan by EventDispatcher()

    // React Native's ReactViewGroup suppresses requestLayout() calls from children.
    // CameraX PreviewView's internal TextureView NEEDS requestLayout() to work.
    // Without this override, the TextureView stays at 0x0 → black screen.
    private val measureAndLayout = Runnable {
        measure(
            MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY)
        )
        layout(left, top, right, bottom)
    }

    override fun requestLayout() {
        super.requestLayout()
        // Post to ensure the measure/layout happens after React's layout pass
        post(measureAndLayout)
    }

    init {
        barcodeScanner = buildBarcodeScanner(null)
        addView(previewView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        overlayView.setBackgroundColor(Color.TRANSPARENT)
        overlayView.isClickable = false
        overlayView.isFocusable = false
        addView(overlayView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    // ─── Touch Handling (Tap-to-Focus + Pinch-to-Zoom) ──────────────────

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        return true
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        var handled = scaleGestureDetector.onTouchEvent(event)

        // Only handle tap-to-focus on single-finger tap (ACTION_UP without pinch in progress)
        if (enableTapToFocus && event.action == MotionEvent.ACTION_UP && !scaleGestureDetector.isInProgress) {
            handleTapToFocus(event.x, event.y)
            handled = true
        }

        return handled || super.onTouchEvent(event)
    }

    private fun handleTapToFocus(x: Float, y: Float) {
        val cam = camera ?: return
        val w = previewView.width.toFloat()
        val h = previewView.height.toFloat()
        if (w <= 0 || h <= 0) return

        val factory = previewView.meteringPointFactory
        val point = factory.createPoint(x, y)
        val action = FocusMeteringAction.Builder(point, FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE)
            .setAutoCancelDuration(3, TimeUnit.SECONDS)
            .build()
        cam.cameraControl.startFocusAndMetering(action)

        overlayView.showFocusIndicator(x, y)
    }

    fun setEnableTapToFocus(enabled: Boolean) {
        enableTapToFocus = enabled
    }

    fun setEnablePinchToZoom(enabled: Boolean) {
        enablePinchToZoom = enabled
    }

    // ─── View Lifecycle ─────────────────────────────────────────────────

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        isViewAttached = true
        tryStartCamera()
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        val w = right - left
        val h = bottom - top
        if (w <= 0 || h <= 0) return

        for (i in 0 until childCount) {
            val child = getChildAt(i)
            child.measure(
                MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY)
            )
            child.layout(0, 0, w, h)
        }

        tryStartCamera()
    }

    // Camera requires: attached + valid dimensions + isActive
    private fun tryStartCamera() {
        if (!isViewAttached || width <= 0 || height <= 0) return
        if (isCameraRunning || isCameraStarting || !isActive) return
        isCameraStarting = true
        post { startCamera() }
    }

    // ─── Props ──────────────────────────────────────────────────────────

    fun setShowBoundingBox(show: Boolean) {
        showBoundingBox = show
        if (!show) overlayView.clearBoxes()
    }

    fun setTorch(enabled: Boolean) {
        torchEnabled = enabled
        camera?.cameraControl?.enableTorch(enabled)
    }

    fun setIsActive(active: Boolean) {
        isActive = active
        if (active) {
            tryStartCamera()
        } else {
            stopCamera()
            overlayView.clearBoxes()
        }
    }

    fun setScanDelay(delay: Long) {
        scanDelayMs = delay
    }

    fun setBarcodeTypes(types: List<String>?) {
        if (types == requestedBarcodeTypes) return
        requestedBarcodeTypes = types
        barcodeScanner.close()
        barcodeScanner = buildBarcodeScanner(types)
        if (isCameraRunning) {
            stopCamera()
            startCamera()
        }
    }

    // ─── Camera Lifecycle ───────────────────────────────────────────────

    fun startCamera() {
        if (isCameraRunning || !isActive) {
            isCameraStarting = false
            return
        }

        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "Camera permission not granted")
            isCameraStarting = false
            return
        }

        Log.d(TAG, "startCamera: requesting CameraProvider...")
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context.applicationContext)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                Log.d(TAG, "startCamera: CameraProvider obtained, binding...")
                bindCamera()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to get CameraProvider", e)
                isCameraStarting = false
            }
        }, ContextCompat.getMainExecutor(context))
    }

    @OptIn(ExperimentalGetImage::class)
    private fun bindCamera() {
        val provider = cameraProvider ?: return
        val lifecycleOwner = findLifecycleOwner() ?: run {
            Log.e(TAG, "No LifecycleOwner found — cannot bind camera")
            return
        }

        provider.unbindAll()

        val preview = Preview.Builder()
            .build()
            .also { it.setSurfaceProvider(previewView.surfaceProvider) }

        val imageAnalysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()

        imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
            val mediaImage = imageProxy.image
            if (mediaImage == null) {
                imageProxy.close()
                return@setAnalyzer
            }

            val cropRect = imageProxy.cropRect
            val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
            barcodeScanner.process(image)
                .addOnSuccessListener { barcodes ->
                    if (barcodes.isNotEmpty()) {
                        // Only consider barcodes that were actually decoded AND within the visible crop area
                        val decodedBarcode = barcodes.firstOrNull { barcode ->
                            barcode.rawValue != null && barcode.boundingBox?.let { box ->
                                cropRect.contains(box.centerX(), box.centerY())
                            } == true
                        }
                        if (decodedBarcode != null) {
                            val rawValue = decodedBarcode.rawValue!!

                            // Show bounding box only for successfully decoded barcodes
                            if (showBoundingBox) {
                                val box = decodedBarcode.boundingBox
                                if (box != null) {
                                    overlayView.updateBoxes(
                                        listOf(RectF(box)),
                                        mediaImage.width,
                                        mediaImage.height,
                                        imageProxy.imageInfo.rotationDegrees
                                    )
                                    scheduleClearOverlay()
                                }
                            }

                            val now = System.currentTimeMillis()
                            val effectiveCooldown = if (scanDelayMs > 0) scanDelayMs else SCAN_COOLDOWN_MS
                            if (now - lastScannedTime < effectiveCooldown && (scanDelayMs > 0 || rawValue == lastScannedValue)) {
                                // Skip: still within cooldown
                            } else {
                                lastScannedValue = rawValue
                                lastScannedTime = now

                                onBarcodeScan(
                                    mapOf(
                                        "data" to rawValue,
                                        "type" to getBarcodeTypeName(decodedBarcode.format),
                                        "format" to decodedBarcode.format
                                    )
                                )
                            }
                        }
                    }
                }
                .addOnCompleteListener { imageProxy.close() }
        }

        try {
            // Shared ViewPort ensures preview and analysis crop the same area
            val viewPort = previewView.viewPort
            camera = if (viewPort != null) {
                provider.bindToLifecycle(
                    lifecycleOwner,
                    CameraSelector.DEFAULT_BACK_CAMERA,
                    UseCaseGroup.Builder()
                        .setViewPort(viewPort)
                        .addUseCase(preview)
                        .addUseCase(imageAnalysis)
                        .build()
                )
            } else {
                provider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, imageAnalysis)
            }
            camera?.cameraControl?.enableTorch(torchEnabled)
            isCameraRunning = true
            isCameraStarting = false
        } catch (e: Exception) {
            Log.e(TAG, "Failed to bind camera use cases", e)
            isCameraStarting = false
        }
    }

    fun stopCamera() {
        cancelClearOverlay()
        cameraProvider?.unbindAll()
        camera = null
        isCameraRunning = false
        isCameraStarting = false
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        isViewAttached = false
        stopCamera()
        cameraExecutor.shutdown()
        barcodeScanner.close()
    }

    // ─── LifecycleOwner Resolution ──────────────────────────────────────

    private fun findLifecycleOwner(): LifecycleOwner? {
        // Prefer ViewTree (official Android approach)
        findViewTreeLifecycleOwner()?.let { owner ->
            if (owner.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) return owner
        }
        // Fallback: walk ContextWrapper chain to find the hosting Activity
        var ctx = context
        while (ctx is android.content.ContextWrapper) {
            if (ctx is android.app.Activity && ctx is LifecycleOwner) return ctx
            ctx = ctx.baseContext
        }
        Log.e(TAG, "No LifecycleOwner found")
        return null
    }

    // ─── Overlay Timer ──────────────────────────────────────────────────

    private fun scheduleClearOverlay() {
        cancelClearOverlay()
        clearOverlayRunnable = Runnable { overlayView.clearBoxes() }
        mainHandler.postDelayed(clearOverlayRunnable!!, OVERLAY_CLEAR_DELAY_MS)
    }

    private fun cancelClearOverlay() {
        clearOverlayRunnable?.let { mainHandler.removeCallbacks(it) }
        clearOverlayRunnable = null
    }

    // ─── Barcode Scanner ────────────────────────────────────────────────

    private fun buildBarcodeScanner(types: List<String>?): BarcodeScanner {
        val builder = BarcodeScannerOptions.Builder()
        if (types.isNullOrEmpty()) {
            builder.setBarcodeFormats(Barcode.FORMAT_ALL_FORMATS)
        } else {
            val formats = types.map { mapBarcodeType(it) }
            builder.setBarcodeFormats(formats.first(), *formats.drop(1).toIntArray())
        }
        return BarcodeScanning.getClient(builder.build())
    }

    private fun mapBarcodeType(name: String): Int = when (name) {
        "QR_CODE" -> Barcode.FORMAT_QR_CODE
        "EAN_8" -> Barcode.FORMAT_EAN_8
        "EAN_13" -> Barcode.FORMAT_EAN_13
        "CODE_128" -> Barcode.FORMAT_CODE_128
        "CODE_39" -> Barcode.FORMAT_CODE_39
        "CODE_93" -> Barcode.FORMAT_CODE_93
        "CODABAR" -> Barcode.FORMAT_CODABAR
        "DATA_MATRIX" -> Barcode.FORMAT_DATA_MATRIX
        "PDF417" -> Barcode.FORMAT_PDF417
        "AZTEC" -> Barcode.FORMAT_AZTEC
        "UPC_A" -> Barcode.FORMAT_UPC_A
        "UPC_E" -> Barcode.FORMAT_UPC_E
        "ITF" -> Barcode.FORMAT_ITF
        else -> Barcode.FORMAT_ALL_FORMATS
    }

    private fun getBarcodeTypeName(format: Int): String = when (format) {
        Barcode.FORMAT_CODE_128 -> "CODE_128"
        Barcode.FORMAT_CODE_39 -> "CODE_39"
        Barcode.FORMAT_CODE_93 -> "CODE_93"
        Barcode.FORMAT_CODABAR -> "CODABAR"
        Barcode.FORMAT_DATA_MATRIX -> "DATA_MATRIX"
        Barcode.FORMAT_EAN_13 -> "EAN_13"
        Barcode.FORMAT_EAN_8 -> "EAN_8"
        Barcode.FORMAT_ITF -> "ITF"
        Barcode.FORMAT_QR_CODE -> "QR_CODE"
        Barcode.FORMAT_UPC_A -> "UPC_A"
        Barcode.FORMAT_UPC_E -> "UPC_E"
        Barcode.FORMAT_PDF417 -> "PDF417"
        Barcode.FORMAT_AZTEC -> "AZTEC"
        else -> "UNKNOWN"
    }

    // ─── Overlay View ───────────────────────────────────────────────────


    private class OverlayView(context: Context) : View(context) {

        private val boxes = mutableListOf<RectF>()
        private var imageWidth = 0
        private var imageHeight = 0
        private var rotation = 0

        // Focus indicator state
        private var focusX = -1f
        private var focusY = -1f
        private var focusAlpha = 0
        private val focusHandler = Handler(Looper.getMainLooper())
        private var focusFadeRunnable: Runnable? = null

        private val boxPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#4CAF50")
            style = Paint.Style.STROKE
            strokeWidth = 4f
            pathEffect = CornerPathEffect(8f)
        }

        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#144CAF50")
            style = Paint.Style.FILL
        }

        private val cornerPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#4CAF50")
            style = Paint.Style.STROKE
            strokeWidth = 8f
            strokeCap = Paint.Cap.ROUND
        }

        private val focusPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.YELLOW
            style = Paint.Style.STROKE
            strokeWidth = 3f
        }

        fun showFocusIndicator(x: Float, y: Float) {
            focusX = x
            focusY = y
            focusAlpha = 255
            postInvalidate()

            focusFadeRunnable?.let { focusHandler.removeCallbacks(it) }
            focusFadeRunnable = Runnable {
                focusAlpha = 0
                focusX = -1f
                focusY = -1f
                postInvalidate()
            }
            focusHandler.postDelayed(focusFadeRunnable!!, 1000)
        }

        fun updateBoxes(newBoxes: List<RectF>, imgW: Int, imgH: Int, rot: Int) {
            boxes.clear()
            boxes.addAll(newBoxes)
            imageWidth = imgW
            imageHeight = imgH
            rotation = rot
            postInvalidate()
        }

        fun clearBoxes() {
            boxes.clear()
            postInvalidate()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)

            // Draw focus indicator
            if (focusX >= 0 && focusY >= 0 && focusAlpha > 0) {
                focusPaint.alpha = focusAlpha
                val size = 70f
                val rect = RectF(focusX - size / 2, focusY - size / 2, focusX + size / 2, focusY + size / 2)
                canvas.drawRoundRect(rect, 4f, 4f, focusPaint)
            }

            if (boxes.isEmpty() || width <= 0 || height <= 0) return

            val viewW = width.toFloat()
            val viewH = height.toFloat()

            // ML Kit returns bounding boxes in the UPRIGHT coordinate space
            // (it applies rotation internally when we pass rotationDegrees to InputImage).
            // The upright image dimensions after rotation:
            val (srcW, srcH) = when (rotation) {
                90, 270 -> imageHeight.toFloat() to imageWidth.toFloat()
                else -> imageWidth.toFloat() to imageHeight.toFloat()
            }
            if (srcW <= 0 || srcH <= 0) return

            // Scale to fill (aspect fill, center crop — same as PreviewView FILL_CENTER)
            val scale = maxOf(viewW / srcW, viewH / srcH)
            val scaledW = srcW * scale
            val scaledH = srcH * scale
            val offsetX = (viewW - scaledW) / 2f
            val offsetY = (viewH - scaledH) / 2f

            for (box in boxes) {
                // Direct mapping — no rotation needed, ML Kit already gives upright coords
                val mapped = RectF(
                    box.left / srcW * scaledW + offsetX,
                    box.top / srcH * scaledH + offsetY,
                    box.right / srcW * scaledW + offsetX,
                    box.bottom / srcH * scaledH + offsetY
                )

                // Expand slightly for visual polish
                mapped.inset(-4f, -4f)

                mapped.left = mapped.left.coerceIn(0f, viewW)
                mapped.top = mapped.top.coerceIn(0f, viewH)
                mapped.right = mapped.right.coerceIn(0f, viewW)
                mapped.bottom = mapped.bottom.coerceIn(0f, viewH)

                if (mapped.width() < 2 || mapped.height() < 2) continue

                canvas.drawRoundRect(mapped, 6f, 6f, fillPaint)
                canvas.drawRoundRect(mapped, 6f, 6f, boxPaint)
                drawCorners(canvas, mapped)
            }
        }

        private fun drawCorners(canvas: Canvas, rect: RectF) {
            val len = minOf(rect.width(), rect.height()) * 0.2f
            val path = Path()

            // Top-left
            path.moveTo(rect.left, rect.top + len)
            path.lineTo(rect.left, rect.top)
            path.lineTo(rect.left + len, rect.top)
            // Top-right
            path.moveTo(rect.right - len, rect.top)
            path.lineTo(rect.right, rect.top)
            path.lineTo(rect.right, rect.top + len)
            // Bottom-right
            path.moveTo(rect.right, rect.bottom - len)
            path.lineTo(rect.right, rect.bottom)
            path.lineTo(rect.right - len, rect.bottom)
            // Bottom-left
            path.moveTo(rect.left + len, rect.bottom)
            path.lineTo(rect.left, rect.bottom)
            path.lineTo(rect.left, rect.bottom - len)

            canvas.drawPath(path, cornerPaint)
        }
    }
}
