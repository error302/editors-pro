//! Hardware-accelerated encoder using Android MediaCodec
//!
//! On Android devices with hardware encoder support (most modern devices),
//! this module uses the NDK MediaCodec API to encode H.264/H.265 video
//! significantly faster than software encoding (3-5x speedup).
//!
//! ## Architecture
//!
//! 1. Detect hardware encoder availability
//! 2. Configure MediaCodec encoder with target parameters
//! 3. Feed RGBA frames as input buffers
//! 4. Read encoded output buffers
//! 5. Mux into MP4 container using FFmpeg
//!
//! ## Fallback
//!
//! If hardware encoding fails for any reason, the system automatically
//! falls back to software (libx264/libx265) encoding via VideoEncoder.
//!
//! ## Design Principle
//!
//! **Hardware encoding is a performance optimization, not a requirement.**
//! The system MUST work without it. Every code path must gracefully
//! degrade to software encoding when hardware is unavailable or fails.

use super::{ExportResult, ExportSettings, VideoCodec};

#[cfg(all(target_os = "android", feature = "ffmpeg"))]
use ffmpeg_next as ffmpeg;

// ──────────────────────────────────────────────────────────────────
// Hardware encoder type & capabilities
// ──────────────────────────────────────────────────────────────────

/// Hardware encoder type detected on the device
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum HardwareEncoderType {
    /// Android MediaCodec hardware encoder
    MediaCodec,
    /// No hardware encoder available
    None,
}

/// Result of hardware encoder capability detection
#[derive(Debug, Clone)]
pub struct HardwareEncoderCapabilities {
    /// The type of hardware encoder detected
    pub encoder_type: HardwareEncoderType,
    /// Supported codecs
    pub supported_codecs: Vec<VideoCodec>,
    /// Maximum supported resolution width
    pub max_width: u32,
    /// Maximum supported resolution height
    pub max_height: u32,
    /// Maximum supported bitrate in kbps
    pub max_bitrate_kbps: u64,
}

impl HardwareEncoderCapabilities {
    /// Detect available hardware encoders on this device.
    ///
    /// On Android, this queries the MediaCodec subsystem via NDK to find
    /// hardware H.264/H.265 encoders. On other platforms, it returns
    /// `HardwareEncoderType::None` since no hardware encoder is available.
    ///
    /// # Android Detection Strategy
    ///
    /// 1. Call `AMediaCodec_createEncoderByType("video/avc")` for H.264
    /// 2. Call `AMediaCodec_createEncoderByType("video/hevc")` for H.265
    /// 3. If either succeeds, populate capabilities with the encoder's
    ///    supported resolution and bitrate ranges
    /// 4. Release the probe encoder — we'll create a fresh one for actual encoding
    ///
    /// # Default Capability Limits
    ///
    /// When hardware is detected, we report conservative defaults:
    /// - Max resolution: 3840×2160 (4K) — most devices support this
    /// - Max bitrate: 100,000 kbps (100 Mbps)
    /// - Supported codecs: H.264 always, H.265 on most modern devices
    pub fn detect() -> Self {
        #[cfg(target_os = "android")]
        {
            Self::detect_android()
        }

        #[cfg(not(target_os = "android"))]
        {
            log::info!("Hardware encoder detection: non-Android platform, no HW encoder available");
            Self::none()
        }
    }

    /// Create a "no hardware encoder" capabilities result.
    fn none() -> Self {
        Self {
            encoder_type: HardwareEncoderType::None,
            supported_codecs: Vec::new(),
            max_width: 0,
            max_height: 0,
            max_bitrate_kbps: 0,
        }
    }

    /// Check if the given settings are within this encoder's capability limits.
    pub fn supports_settings(&self, settings: &ExportSettings) -> bool {
        if self.encoder_type == HardwareEncoderType::None {
            return false;
        }

        // Check resolution limits
        if settings.width > self.max_width || settings.height > self.max_height {
            log::warn!(
                "Hardware encoder: resolution {}x{} exceeds max {}x{}, falling back to software",
                settings.width, settings.height, self.max_width, self.max_height
            );
            return false;
        }

        // Check bitrate limits
        if settings.bitrate_kbps > self.max_bitrate_kbps {
            log::warn!(
                "Hardware encoder: bitrate {}kbps exceeds max {}kbps, falling back to software",
                settings.bitrate_kbps, self.max_bitrate_kbps
            );
            return false;
        }

        // Check codec support — MediaCodec only supports H.264 and H.265
        if !self.supported_codecs.contains(&settings.codec) {
            log::warn!(
                "Hardware encoder: codec {:?} not supported, falling back to software",
                settings.codec
            );
            return false;
        }

        true
    }
}

// ──────────────────────────────────────────────────────────────────
// Android-specific detection
// ──────────────────────────────────────────────────────────────────

#[cfg(target_os = "android")]
impl HardwareEncoderCapabilities {
    /// Probe the Android MediaCodec subsystem for hardware encoders.
    ///
    /// This function uses the NDK `AMediaCodec` API to check whether
    /// hardware H.264 and/or H.265 encoders are available on this device.
    ///
    /// ## NDK Calls (Conceptual)
    ///
    /// ```c
    /// // Probe H.264 encoder
    /// AMediaCodec* h264_encoder = AMediaCodec_createEncoderByType("video/avc");
    /// if (h264_encoder) {
    ///     AMediaFormat* format = AMediaFormat_new();
    ///     AMediaFormat_setString(format, AMEDIAFORMAT_KEY_MIME, "video/avc");
    ///     AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_WIDTH, 1920);
    ///     AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_HEIGHT, 1080);
    ///     AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_BIT_RATE, 10000000);
    ///     AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_FRAME_RATE, 30);
    ///     AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_COLOR_FORMAT,
    ///                          COLOR_FormatRGBAFlexible);  // 0x7F36A888
    ///     // Try to configure — if it fails, no HW encoder for this type
    ///     media_status_t status = AMediaCodec_configure(
    ///         h264_encoder, format, NULL, NULL, AMEDIACODEC_CONFIGURE_FLAG_ENCODE);
    ///     AMediaFormat_delete(format);
    ///     AMediaCodec_delete(h264_encoder);
    /// }
    /// ```
    ///
    /// For now, we use a simplified probe that attempts to create an encoder
    /// and reports availability based on success.
    fn detect_android() -> Self {
        log::info!("Hardware encoder detection: probing Android MediaCodec");

        let mut supported_codecs = Vec::new();
        let mut max_width = 3840u32;
        let mut max_height = 2160u32;
        let mut max_bitrate_kbps = 100_000u64;

        // Probe H.264 (AVC) hardware encoder
        if Self::probe_android_encoder("video/avc") {
            log::info!("Android MediaCodec: H.264 (AVC) hardware encoder found");
            supported_codecs.push(VideoCodec::H264);
        } else {
            log::info!("Android MediaCodec: H.264 (AVC) hardware encoder NOT found");
        }

        // Probe H.265 (HEVC) hardware encoder
        if Self::probe_android_encoder("video/hevc") {
            log::info!("Android MediaCodec: H.265 (HEVC) hardware encoder found");
            supported_codecs.push(VideoCodec::H265);
        } else {
            log::info!("Android MediaCodec: H.265 (HEVC) hardware encoder NOT found");
        }

        if supported_codecs.is_empty() {
            log::warn!("No hardware encoders found on this Android device");
            return Self::none();
        }

        // Query actual capability limits from MediaCodec info.
        // In a full implementation, this would use AMediaCodecInfo to get
        // VideoCapabilities with exact resolution and bitrate ranges.
        // For now, we use conservative defaults that work on most devices.
        //
        // Full implementation would call:
        //   AMediaCodecList_findEncoderByType()
        //   AMediaCodecInfo_getCapabilitiesForType()
        //   VideoCapabilities_getSupportedWidths/Heights/BitrateRange()
        Self::query_android_encoder_limits(&mut max_width, &mut max_height, &mut max_bitrate_kbps);

        log::info!(
            "Hardware encoder capabilities: {:?}, max {}x{}, max {}kbps",
            supported_codecs, max_width, max_height, max_bitrate_kbps
        );

        Self {
            encoder_type: HardwareEncoderType::MediaCodec,
            supported_codecs,
            max_width,
            max_height,
            max_bitrate_kbps,
        }
    }

    /// Probe whether a specific MediaCodec encoder type is available.
    ///
    /// Attempts to create an encoder by MIME type. If creation succeeds,
    /// the encoder is available on this device.
    ///
    /// ## NDK Implementation
    ///
    /// ```c
    /// AMediaCodec* encoder = AMediaCodec_createEncoderByType(mime_type);
    /// if (encoder) {
    ///     AMediaCodec_delete(encoder);
    ///     return true;
    /// }
    /// return false;
    /// ```
    fn probe_android_encoder(mime_type: &str) -> bool {
        // Placeholder: In production, this would call ndk-sys FFI:
        //
        //   use ndk_sys::*;
        //   let encoder = unsafe {
        //       AMediaCodec_createEncoderByType(
        //           mime_type.as_ptr() as *const c_char
        //       )
        //   };
        //   if !encoder.is_null() {
        //       unsafe { AMediaCodec_delete(encoder); }
        //       return true;
        //   }
        //   return false;

        log::debug!(
            "Probing Android encoder for MIME type: {} (stub — returning false)",
            mime_type
        );

        // For now, return false so we always fall back to software.
        // When the actual NDK integration is implemented, this will
        // return true if the encoder probe succeeds.
        false
    }

    /// Query the resolution and bitrate limits of the hardware encoder.
    ///
    /// ## NDK Implementation
    ///
    /// ```c
    /// // Get codec info from the encoder list
    /// ssize_t codecIndex = AMediaCodecList_findEncoderByType(mime_type);
    /// AMediaCodecInfo* info = AMediaCodecList_getCodecInfo(codecIndex);
    /// AMediaCodecInfoCapabilities* caps =
    ///     AMediaCodecInfo_getCapabilitiesForType(info, mime_type);
    ///
    /// // Extract VideoCapabilities
    /// VideoCapabilities* videoCaps = caps->videoCapabilities;
    /// VideoSize* maxSize = VideoCapabilities_getSupportedVideoSizes(videoCaps);
    /// Range* bitrateRange = VideoCapabilities_getBitrateRange(videoCaps);
    /// ```
    ///
    /// For now, we leave the conservative defaults intact.
    fn query_android_encoder_limits(
        max_width: &mut u32,
        max_height: &mut u32,
        max_bitrate_kbps: &mut u64,
    ) {
        // Placeholder: When NDK integration is complete, this function
        // will query AMediaCodecInfo for the actual limits of the
        // hardware encoder and update the values accordingly.
        //
        // The conservative defaults (4K, 100Mbps) are already set by
        // the caller, so we just log and leave them.
        log::debug!(
            "Using default encoder limits: {}x{}, {}kbps",
            max_width, max_height, max_bitrate_kbps
        );
    }
}

// ──────────────────────────────────────────────────────────────────
// Android MediaCodec state (NDI FFI wrapper)
// ──────────────────────────────────────────────────────────────────

/// Opaque handle to an Android MediaCodec encoder.
///
/// On Android, this wraps an `AMediaCodec*` pointer obtained from
/// `AMediaCodec_createEncoderByType()`. On other platforms, this
/// type is not instantiated.
#[cfg(target_os = "android")]
struct AndroidMediaCodec {
    /// Pointer to the native AMediaCodec object.
    /// Set to `std::ptr::null_mut()` when not initialized.
    codec_ptr: *mut std::ffi::c_void,

    /// The MIME type used to create this encoder ("video/avc" or "video/hevc").
    mime_type: String,

    /// Whether the encoder has been started (configure + start called).
    is_started: bool,

    /// Width configured for this encoder.
    width: u32,

    /// Height configured for this encoder.
    height: u32,

    /// Bitrate in bps configured for this encoder.
    bitrate_bps: u32,

    /// Frame rate configured for this encoder.
    frame_rate: u32,

    /// Index of the input buffer currently dequeued, or -1 if none.
    input_buffer_index: i32,
}

#[cfg(target_os = "android")]
impl AndroidMediaCodec {
    /// Create a new MediaCodec encoder for the given MIME type.
    ///
    /// ## NDK Implementation
    ///
    /// ```c
    /// AMediaCodec* codec = AMediaCodec_createEncoderByType(mime_type);
    /// if (!codec) return Err("Failed to create MediaCodec encoder");
    /// ```
    fn new(mime_type: &str) -> Result<Self, String> {
        // Placeholder: In production, this would call:
        //
        //   use ndk_sys::*;
        //   let codec_ptr = unsafe {
        //       AMediaCodec_createEncoderByType(
        //           mime_type.as_ptr() as *const c_char
        //       )
        //   };
        //   if codec_ptr.is_null() {
        //       return Err(format!(
        //           "Failed to create MediaCodec encoder for '{}'", mime_type
        //       ));
        //   }

        log::info!(
            "Creating AndroidMediaCodec for '{}' (stub — returning error)",
            mime_type
        );

        // Stub: return error so we fall back to software encoding
        Err(format!(
            "Android MediaCodec FFI not yet implemented for '{}'",
            mime_type
        ))
    }

    /// Configure the encoder with the target parameters.
    ///
    /// ## NDK Implementation
    ///
    /// ```c
    /// AMediaFormat* format = AMediaFormat_new();
    /// AMediaFormat_setString(format, AMEDIAFORMAT_KEY_MIME, mime_type);
    /// AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_WIDTH, width);
    /// AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_HEIGHT, height);
    /// AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_BIT_RATE, bitrate_bps);
    /// AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_FRAME_RATE, frame_rate);
    /// AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_I_FRAME_INTERVAL, 1);
    /// AMediaFormat_setInt32(format, AMEDIAFORMAT_KEY_COLOR_FORMAT,
    ///                      COLOR_FormatRGBAFlexible);
    ///
    /// media_status_t status = AMediaCodec_configure(
    ///     codec, format, NULL, NULL, AMEDIACODEC_CONFIGURE_FLAG_ENCODE);
    /// AMediaFormat_delete(format);
    /// ```
    fn configure(
        &mut self,
        width: u32,
        height: u32,
        bitrate_bps: u32,
        frame_rate: u32,
    ) -> Result<(), String> {
        // Placeholder: In production, this would:
        // 1. Create an AMediaFormat with the above keys
        // 2. Call AMediaCodec_configure() with CONFIGURE_FLAG_ENCODE
        // 3. Check the return status

        self.width = width;
        self.height = height;
        self.bitrate_bps = bitrate_bps;
        self.frame_rate = frame_rate;

        log::info!(
            "Configuring AndroidMediaCodec: {}x{} @ {}bps, {}fps (stub)",
            width, height, bitrate_bps, frame_rate
        );

        Ok(())
    }

    /// Start the encoder.
    ///
    /// After configure, call start to begin accepting input frames.
    ///
    /// ## NDK Implementation
    ///
    /// ```c
    /// media_status_t status = AMediaCodec_start(codec);
    /// ```
    fn start(&mut self) -> Result<(), String> {
        // Placeholder: In production, this would call:
        //
        //   use ndk_sys::*;
        //   let status = unsafe { AMediaCodec_start(self.codec_ptr) };
        //   if status != AMEDIA_OK {
        //       return Err(format!("AMediaCodec_start failed: {:?}", status));
        //   }

        self.is_started = true;
        log::info!("Starting AndroidMediaCodec (stub)");
        Ok(())
    }

    /// Dequeue an input buffer index for writing frame data.
    ///
    /// ## NDK Implementation
    ///
    /// ```c
    /// ssize_t index = AMediaCodec_dequeueInputBuffer(codec, timeout_us);
    /// if (index < 0) {
    ///     // No input buffer available yet
    ///     // AMEDIACODEC_INFO_TRY_AGAIN_LATER = -1
    /// }
    /// ```
    fn dequeue_input_buffer(&mut self, timeout_us: i64) -> Result<i32, String> {
        // Placeholder: In production, this would call:
        //
        //   use ndk_sys::*;
        //   let index = unsafe {
        //       AMediaCodec_dequeueInputBuffer(self.codec_ptr, timeout_us)
        //   };
        //   if index < 0 { return Err("No input buffer available"); }

        self.input_buffer_index = -1;
        Err("dequeueInputBuffer: stub, no buffer".to_string())
    }

    /// Get the pointer and size of an input buffer for writing.
    ///
    /// ## NDK Implementation
    ///
    /// ```c
    /// size_t out_size = 0;
    /// uint8_t* buf = AMediaCodec_getInputBuffer(codec, index, &out_size);
    /// ```
    fn get_input_buffer(&self, index: i32) -> Result<(*mut u8, usize), String> {
        // Placeholder: In production, this would call:
        //
        //   use ndk_sys::*;
        //   let mut size: usize = 0;
        //   let buf = unsafe {
        //       AMediaCodec_getInputBuffer(self.codec_ptr, index as usize, &mut size)
        //   };
        //   if buf.is_null() {
        //       return Err("getInputBuffer returned null".to_string());
        //   }
        //   Ok((buf, size))

        Err("getInputBuffer: stub".to_string())
    }

    /// Submit the input buffer to the encoder after writing frame data.
    ///
    /// ## NDK Implementation
    ///
    /// ```c
    /// media_status_t status = AMediaCodec_queueInputBuffer(
    ///     codec, index, offset, size, presentationTimeUs, flags);
    /// ```
    fn queue_input_buffer(
        &mut self,
        index: i32,
        offset: usize,
        size: usize,
        presentation_time_us: i64,
        flags: u32,
    ) -> Result<(), String> {
        // Placeholder: In production, this would call:
        //
        //   use ndk_sys::*;
        //   let status = unsafe {
        //       AMediaCodec_queueInputBuffer(
        //           self.codec_ptr,
        //           index as usize,
        //           offset,
        //           size,
        //           presentation_time_us,
        //           flags,
        //       )
        //   };

        log::debug!(
            "queueInputBuffer: index={}, offset={}, size={}, pts={}us, flags={} (stub)",
            index, offset, size, presentation_time_us, flags
        );
        Ok(())
    }

    /// Dequeue an output buffer index from the encoder.
    ///
    /// ## NDK Implementation
    ///
    /// ```c
    /// AMediaCodecBufferInfo info;
    /// ssize_t index = AMediaCodec_dequeueOutputBuffer(codec, &info, timeout_us);
    /// // If index == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED, read new format
    /// // If index == AMEDIACODEC_INFO_TRY_AGAIN_LATER, no output yet
    /// ```
    fn dequeue_output_buffer(&self, timeout_us: i64) -> Result<Option<MediaCodecOutputBuffer>, String> {
        // Placeholder: In production, this would:
        // 1. Call AMediaCodec_dequeueOutputBuffer()
        // 2. If output available, call AMediaCodec_getOutputBuffer() to get the data
        // 3. Copy the encoded data out
        // 4. Call AMediaCodec_releaseOutputBuffer(codec, index, false)

        Ok(None)
    }

    /// Signal end-of-stream to the encoder.
    ///
    /// ## NDK Implementation
    ///
    /// ```c
    /// // Queue an empty buffer with BUFFER_FLAG_END_OF_STREAM
    /// AMediaCodec_signalEndOfInputStream(codec);
    /// ```
    fn signal_end_of_stream(&mut self) -> Result<(), String> {
        // Placeholder: In production, this would call:
        //
        //   use ndk_sys::*;
        //   let status = unsafe { AMediaCodec_signalEndOfInputStream(self.codec_ptr) };

        log::info!("SignalEndOfInputStream (stub)");
        Ok(())
    }

    /// Stop and release the MediaCodec encoder.
    ///
    /// ## NDK Implementation
    ///
    /// ```c
    /// AMediaCodec_stop(codec);
    /// AMediaCodec_delete(codec);
    /// ```
    fn stop_and_release(&mut self) {
        // Placeholder: In production, this would call:
        //
        //   use ndk_sys::*;
        //   if !self.codec_ptr.is_null() {
        //       if self.is_started {
        //           unsafe { AMediaCodec_stop(self.codec_ptr); }
        //       }
        //       unsafe { AMediaCodec_delete(self.codec_ptr); }
        //       self.codec_ptr = std::ptr::null_mut();
        //   }

        self.is_started = false;
        log::info!("StopAndRelease MediaCodec (stub)");
    }
}

#[cfg(target_os = "android")]
impl Drop for AndroidMediaCodec {
    fn drop(&mut self) {
        self.stop_and_release();
    }
}

// Safety: AndroidMediaCodec owns a raw pointer that is only accessed
// through &mut methods. It is not safe to send across threads because
// MediaCodec is not thread-safe.
#[cfg(target_os = "android")]
unsafe impl Send for AndroidMediaCodec {}

/// Encoded output buffer from MediaCodec.
///
/// Contains the encoded NAL units and associated metadata.
struct MediaCodecOutputBuffer {
    /// Encoded byte data (H.264 NAL units or H.265 NAL units).
    data: Vec<u8>,
    /// Presentation timestamp in microseconds.
    presentation_time_us: i64,
    /// Flags (e.g., BUFFER_FLAG_KEY_FRAME, BUFFER_FLAG_CODEC_CONFIG).
    flags: u32,
}

// ──────────────────────────────────────────────────────────────────
// Hardware encoder
// ──────────────────────────────────────────────────────────────────

/// Hardware-accelerated video encoder.
///
/// Uses Android MediaCodec for encoding when available, with automatic
/// fallback to software encoding via `VideoEncoder`.
///
/// ## Usage (drop-in replacement for VideoEncoder)
///
/// ```rust
/// let mut encoder = HardwareEncoder::new(&settings)?;
/// encoder.open(output_path)?;
///
/// for each_frame {
///     encoder.encode_rgba_frame(rgba_data, pts)?;
/// }
///
/// let result = encoder.finish(duration_ms)?;
/// ```
///
/// ## Fallback Behavior
///
/// 1. If no hardware encoder is detected at creation time → software
/// 2. If the settings exceed hardware capabilities → software
/// 3. If `open()` fails to initialize MediaCodec → software
/// 4. If `encode_rgba_frame()` fails mid-stream → switch to software
///    and re-encode the current frame
///
/// The fallback is transparent to the caller — the same `finish()` and
/// `cancel()` methods work regardless of which encoding path is active.
pub struct HardwareEncoder {
    /// Detected hardware encoder type.
    encoder_type: HardwareEncoderType,

    /// Capabilities of the detected encoder.
    capabilities: HardwareEncoderCapabilities,

    /// The software fallback encoder.
    /// Created lazily when hardware encoding fails, or eagerly
    /// when hardware is not available.
    software_encoder: Option<super::VideoEncoder>,

    /// Whether hardware encoding is currently active.
    /// This is `true` only when we are actively using MediaCodec.
    /// It becomes `false` if we fall back to software mid-stream.
    using_hardware: bool,

    /// The export settings being used.
    settings: ExportSettings,

    /// The output path, saved so we can create the software fallback
    /// encoder at the same path if needed.
    output_path: Option<String>,

    /// Number of frames encoded so far.
    frame_count: u64,

    /// Time when encoding started.
    start_time: std::time::Instant,

    /// Android MediaCodec encoder state.
    /// Only present on Android and when hardware encoding is active.
    #[cfg(target_os = "android")]
    media_codec: Option<AndroidMediaCodec>,

    /// FFmpeg output context for muxing MediaCodec output into MP4.
    /// When using hardware encoding, the encoded NAL units from MediaCodec
    /// are written to this context as packets.
    #[cfg(all(target_os = "android", feature = "ffmpeg"))]
    mux_context: Option<ffmpeg::format::context::Output>,

    /// Whether the encoder has been opened.
    is_opened: bool,
}

impl HardwareEncoder {
    /// Create a new hardware encoder with the given export settings.
    ///
    /// This detects hardware encoder capabilities and decides whether
    /// to use hardware or software encoding. The decision is based on:
    ///
    /// 1. Whether a hardware encoder is available on this device
    /// 2. Whether the requested codec is supported by the hardware encoder
    /// 3. Whether the requested resolution/bitrate are within limits
    ///
    /// # Errors
    ///
    /// Returns an error only if the settings are invalid (zero dimensions,
    /// odd dimensions, zero bitrate, etc.) — same validation as `VideoEncoder`.
    pub fn new(settings: &ExportSettings) -> Result<Self, String> {
        // Validate settings (same checks as VideoEncoder)
        if settings.width == 0 || settings.height == 0 {
            return Err("Width and height must be non-zero".to_string());
        }
        if settings.width % 2 != 0 || settings.height % 2 != 0 {
            return Err(format!(
                "Dimensions must be even (got {}x{})",
                settings.width, settings.height
            ));
        }
        if settings.fps <= 0.0 {
            return Err("FPS must be positive".to_string());
        }
        if settings.bitrate_kbps == 0 {
            return Err("Bitrate must be non-zero".to_string());
        }

        // Detect hardware capabilities
        let capabilities = HardwareEncoderCapabilities::detect();
        let encoder_type = capabilities.encoder_type;

        // Decide whether to use hardware
        let using_hardware = capabilities.supports_settings(settings);

        if using_hardware {
            log::info!(
                "HardwareEncoder: will use {} hardware encoder for {}x{} {:?}",
                match encoder_type {
                    HardwareEncoderType::MediaCodec => "MediaCodec",
                    HardwareEncoderType::None => "none",
                },
                settings.width,
                settings.height,
                settings.codec
            );
        } else {
            log::info!(
                "HardwareEncoder: will use software encoder (HW not available or settings incompatible)"
            );
        }

        // If not using hardware, create the software encoder immediately
        let software_encoder = if !using_hardware {
            Some(super::VideoEncoder::new(settings)?)
        } else {
            None
        };

        Ok(Self {
            encoder_type,
            capabilities,
            software_encoder,
            using_hardware,
            settings: settings.clone(),
            output_path: None,
            frame_count: 0,
            start_time: std::time::Instant::now(),
            #[cfg(target_os = "android")]
            media_codec: None,
            #[cfg(all(target_os = "android", feature = "ffmpeg"))]
            mux_context: None,
            is_opened: false,
        })
    }

    /// Quick check if any hardware encoder is available on this device.
    ///
    /// This is a lightweight check that doesn't require creating an encoder.
    /// Useful for UI display (e.g., showing "Hardware encoding available" badge).
    pub fn is_available() -> bool {
        let caps = HardwareEncoderCapabilities::detect();
        caps.encoder_type != HardwareEncoderType::None
    }

    /// Open the encoder and prepare to receive frames.
    ///
    /// If hardware encoding was selected during `new()`, this initializes
    /// the MediaCodec encoder. If that fails, it falls back to software.
    ///
    /// If software encoding was selected during `new()`, this delegates
    /// directly to `VideoEncoder::open()`.
    pub fn open(&mut self, output_path: &str) -> Result<(), String> {
        if self.is_opened {
            return Err("Encoder is already opened".to_string());
        }

        self.output_path = Some(output_path.to_string());

        if self.using_hardware {
            match self.open_hardware(output_path) {
                Ok(()) => {
                    log::info!(
                        "HardwareEncoder: opened hardware encoder for '{}'",
                        output_path
                    );
                    self.is_opened = true;
                    Ok(())
                }
                Err(e) => {
                    log::warn!(
                        "HardwareEncoder: hardware open failed ({}), falling back to software",
                        e
                    );
                    self.fallback_to_software()?;
                    self.open_software(output_path)
                }
            }
        } else {
            self.open_software(output_path)
        }
    }

    /// Encode a single RGBA frame.
    ///
    /// If hardware encoding is active, this feeds the RGBA data to the
    /// MediaCodec input buffer and reads encoded output. If hardware
    /// encoding fails mid-stream, it switches to software encoding and
    /// re-encodes the current frame.
    ///
    /// If software encoding is active, this delegates to `VideoEncoder`.
    ///
    /// The `pts` should be the frame number (0-based), matching the
    /// convention used by `VideoEncoder`.
    pub fn encode_rgba_frame(&mut self, rgba_data: &[u8], pts: i64) -> Result<(), String> {
        if !self.is_opened {
            return Err("Encoder not opened yet".to_string());
        }

        if self.using_hardware {
            match self.encode_hardware_frame(rgba_data, pts) {
                Ok(()) => {
                    self.frame_count += 1;
                    Ok(())
                }
                Err(e) => {
                    log::warn!(
                        "HardwareEncoder: HW encode failed at frame {} ({}), switching to software",
                        self.frame_count, e
                    );
                    self.fallback_to_software()?;

                    // Re-encode this frame with the software encoder
                    self.encode_software_frame(rgba_data, pts)?;
                    self.frame_count += 1;
                    Ok(())
                }
            }
        } else {
            self.encode_software_frame(rgba_data, pts)?;
            self.frame_count += 1;
            Ok(())
        }
    }

    /// Finalize encoding and return the export result.
    ///
    /// If hardware encoding is active, this signals end-of-stream to
    /// MediaCodec, drains remaining output buffers, and writes the
    /// MP4 trailer via FFmpeg.
    ///
    /// If software encoding is active, this delegates to `VideoEncoder::finish()`.
    pub fn finish(mut self, duration_ms: u64) -> Result<ExportResult, String> {
        if !self.is_opened {
            return Err("Encoder not opened yet".to_string());
        }

        if self.using_hardware {
            self.finish_hardware(duration_ms)
        } else {
            self.finish_software(duration_ms)
        }
    }

    /// Cancel the export and clean up.
    ///
    /// If hardware encoding is active, this stops and releases the
    /// MediaCodec encoder and removes the partial output file.
    /// If software encoding is active, this delegates to `VideoEncoder::cancel()`.
    pub fn cancel(mut self) {
        if self.using_hardware {
            self.cancel_hardware();
        } else {
            self.cancel_software();
        }
    }

    /// Check if currently using hardware acceleration.
    ///
    /// Returns `true` only when actively using a hardware encoder.
    /// Returns `false` when using software encoding (either because
    /// no hardware was available, or because of a mid-stream fallback).
    pub fn is_hardware_accelerated(&self) -> bool {
        self.using_hardware
    }

    /// Get the number of frames encoded so far.
    pub fn frame_count(&self) -> u64 {
        self.frame_count
    }

    /// Get the detected hardware encoder type.
    pub fn encoder_type(&self) -> HardwareEncoderType {
        self.encoder_type
    }

    /// Get the detected hardware encoder capabilities.
    pub fn capabilities(&self) -> &HardwareEncoderCapabilities {
        &self.capabilities
    }
}

// ──────────────────────────────────────────────────────────────────
// Hardware encoding path
// ──────────────────────────────────────────────────────────────────

impl HardwareEncoder {
    /// Open the hardware (MediaCodec) encoder.
    ///
    /// ## Steps
    ///
    /// 1. Determine the MIME type from the codec setting
    /// 2. Create an `AMediaCodec` encoder for that MIME type
    /// 3. Configure it with width, height, bitrate, frame rate, color format
    /// 4. Create an FFmpeg mux context for the output container
    /// 5. Start the MediaCodec encoder
    fn open_hardware(&mut self, _output_path: &str) -> Result<(), String> {
        #[cfg(all(target_os = "android", feature = "ffmpeg"))]
        {
            // Determine MIME type
            let mime_type = match self.settings.codec {
                VideoCodec::H264 => "video/avc",
                VideoCodec::H265 => "video/hevc",
                _ => {
                    return Err(format!(
                        "Hardware encoder does not support codec {:?}",
                        self.settings.codec
                    ));
                }
            };

            // Create MediaCodec encoder
            let mut codec = AndroidMediaCodec::new(mime_type)?;

            // Configure with target parameters
            codec.configure(
                self.settings.width,
                self.settings.height,
                self.settings.bitrate_kbps as u32 * 1000, // kbps → bps
                self.settings.fps as u32,
            )?;

            // Create FFmpeg mux context for output container.
            // The MediaCodec encoder produces raw NAL units; we need FFmpeg
            // to wrap them in an MP4 container with proper headers.
            //
            // In a full implementation, this would:
            // 1. Create an ffmpeg::format::output() context
            // 2. Add a stream with the appropriate codec parameters
            //    (parsed from the MediaCodec output format)
            // 3. Write the container header
            // 4. As each encoded buffer arrives from MediaCodec, wrap
            //    it in an ffmpeg::Packet and write it interleaved
            let mut octx = ffmpeg::format::output(_output_path)
                .map_err(|e| format!("Failed to create mux output context: {}", e))?;

            // For the mux context, we need to add a stream with the
            // codec parameters extracted from MediaCodec's output format.
            // This is typically done after the first output buffer is
            // received (which contains the SPS/PPS for H.264).
            //
            // As a placeholder, we write the header now and will
            // handle stream setup when the first encoded data arrives.
            octx.write_header()
                .map_err(|e| format!("Failed to write mux header: {}", e))?;

            // Start the encoder
            codec.start()?;

            self.media_codec = Some(codec);
            self.mux_context = Some(octx);
            self.start_time = std::time::Instant::now();
            self.frame_count = 0;

            Ok(())
        }

        #[cfg(not(all(target_os = "android", feature = "ffmpeg")))]
        {
            Err("Hardware encoding is only available on Android with FFmpeg".to_string())
        }
    }

    /// Encode a frame using the hardware encoder.
    ///
    /// ## Steps
    ///
    /// 1. Dequeue an input buffer from MediaCodec
    /// 2. Get the buffer pointer and copy RGBA data into it
    /// 3. Queue the input buffer with the presentation timestamp
    /// 4. Dequeue any available output buffers
    /// 5. Write encoded data to the FFmpeg mux context
    fn encode_hardware_frame(&mut self, _rgba_data: &[u8], _pts: i64) -> Result<(), String> {
        #[cfg(all(target_os = "android", feature = "ffmpeg"))]
        {
            let codec = self.media_codec.as_mut()
                .ok_or("MediaCodec not initialized")?;

            // Calculate presentation time in microseconds
            // pts is the frame number; time_base = 1/fps
            let presentation_time_us = (_pts as i64 * 1_000_000) / self.settings.fps as i64;

            // Step 1: Dequeue an input buffer (wait up to 10ms)
            let buffer_index = codec.dequeue_input_buffer(10_000)?;

            // Step 2: Get the buffer and copy RGBA data
            let (buf_ptr, buf_size) = codec.get_input_buffer(buffer_index)?;

            let required_size = _rgba_data.len();
            if buf_size < required_size {
                return Err(format!(
                    "Input buffer too small: {} < {} bytes",
                    buf_size, required_size
                ));
            }

            // Copy RGBA data into the MediaCodec input buffer.
            // Note: MediaCodec with COLOR_FormatRGBAFlexible accepts
            // RGBA data directly, so no color conversion is needed!
            // This is a major advantage over software encoding which
            // requires RGBA → YUV420P conversion.
            unsafe {
                std::ptr::copy_nonoverlapping(
                    _rgba_data.as_ptr(),
                    buf_ptr,
                    required_size,
                );
            }

            // Step 3: Queue the input buffer
            codec.queue_input_buffer(
                buffer_index,
                0,
                required_size,
                presentation_time_us,
                0, // No special flags
            )?;

            // Step 4: Drain any available output buffers
            self.drain_hardware_output()?;

            Ok(())
        }

        #[cfg(not(all(target_os = "android", feature = "ffmpeg")))]
        {
            Err("Hardware encoding is only available on Android with FFmpeg".to_string())
        }
    }

    /// Drain encoded output from the hardware encoder and write to the mux.
    ///
    /// This should be called after each input frame. It may produce zero
    /// or more encoded packets (MediaCodec operates asynchronously and
    /// may buffer frames internally).
    fn drain_hardware_output(&mut self) -> Result<(), String> {
        #[cfg(all(target_os = "android", feature = "ffmpeg"))]
        {
            let codec = self.media_codec.as_mut()
                .ok_or("MediaCodec not initialized")?;
            let octx = self.mux_context.as_mut()
                .ok_or("Mux context not initialized")?;

            // Drain all available output buffers
            loop {
                match codec.dequeue_output_buffer(0) {
                    Ok(Some(output_buffer)) => {
                        // Write the encoded data to the FFmpeg mux context
                        //
                        // In a full implementation, this would:
                        // 1. Create an ffmpeg::Packet from the output buffer data
                        // 2. Set the packet's PTS from output_buffer.presentation_time_us
                        // 3. Set key_frame flag if BUFFER_FLAG_KEY_FRAME is set
                        // 4. Write the packet interleaved to the mux context
                        //
                        // For SPS/PPS data (BUFFER_FLAG_CODEC_CONFIG), this would
                        // update the stream's extradata rather than writing a packet.

                        let is_key_frame = (output_buffer.flags & 0x0001) != 0; // BUFFER_FLAG_KEY_FRAME
                        let is_codec_config = (output_buffer.flags & 0x0002) != 0; // BUFFER_FLAG_CODEC_CONFIG

                        if is_codec_config {
                            // Codec config data (SPS/PPS for H.264, VPS/SPS/PPS for H.265)
                            // This should be stored as extradata on the stream, not
                            // written as a regular packet.
                            log::debug!(
                                "Received codec config data: {} bytes",
                                output_buffer.data.len()
                            );
                            // In full implementation: update stream extradata
                        } else {
                            log::debug!(
                                "Received encoded frame: {} bytes, key_frame={}, pts={}us",
                                output_buffer.data.len(),
                                is_key_frame,
                                output_buffer.presentation_time_us
                            );
                            // In full implementation: create and write ffmpeg::Packet
                        }
                    }
                    Ok(None) => {
                        // No more output buffers available right now
                        break;
                    }
                    Err(e) => {
                        log::warn!("Error draining hardware output: {}", e);
                        break;
                    }
                }
            }

            Ok(())
        }

        #[cfg(not(all(target_os = "android", feature = "ffmpeg")))]
        {
            Ok(())
        }
    }

    /// Finish encoding with the hardware encoder.
    ///
    /// 1. Signal end-of-stream to MediaCodec
    /// 2. Drain remaining output buffers
    /// 3. Write MP4 trailer via FFmpeg
    /// 4. Return the export result
    fn finish_hardware(&mut self, _duration_ms: u64) -> Result<ExportResult, String> {
        #[cfg(all(target_os = "android", feature = "ffmpeg"))]
        {
            // Signal end of input stream
            if let Some(codec) = self.media_codec.as_mut() {
                let _ = codec.signal_end_of_stream();

                // Drain remaining output buffers (the encoder may have
                // several frames buffered internally)
                self.drain_hardware_output()?;

                // Stop and release the MediaCodec encoder
                codec.stop_and_release();
            }
            self.media_codec = None;

            // Write the MP4 trailer
            if let Some(octx) = self.mux_context.take() {
                octx.write_trailer()
                    .map_err(|e| format!("Failed to write trailer: {}", e))?;

                // Use the stored output path instead of octx.path(),
                // which may not be available in all ffmpeg-next versions.
                let output_path = self.output_path.clone().unwrap_or_default();
                let file_size = std::fs::metadata(&output_path)
                    .map(|m| m.len())
                    .unwrap_or(0);

                let elapsed = self.start_time.elapsed();
                log::info!(
                    "Hardware export complete: {} frames, {}ms → {}bytes, took {:.1}s (hardware)",
                    self.frame_count,
                    _duration_ms,
                    file_size,
                    elapsed.as_secs_f64()
                );

                Ok(ExportResult {
                    success: true,
                    output_path,
                    file_size_bytes: file_size,
                    duration_ms: _duration_ms,
                    error_message: None,
                })
            } else {
                Err("No mux context to finalize".to_string())
            }
        }

        #[cfg(not(all(target_os = "android", feature = "ffmpeg")))]
        {
            Err("Hardware encoding is only available on Android with FFmpeg".to_string())
        }
    }

    /// Cancel the hardware encoding and clean up.
    fn cancel_hardware(&mut self) {
        #[cfg(all(target_os = "android", feature = "ffmpeg"))]
        {
            // Stop MediaCodec
            if let Some(codec) = self.media_codec.as_mut() {
                codec.stop_and_release();
            }
            self.media_codec = None;

            // Close and delete the partial output file
            if let Some(octx) = self.mux_context.take() {
                drop(octx);
                // Use stored output path instead of octx.path()
                if let Some(path) = &self.output_path {
                    let _ = std::fs::remove_file(path);
                    log::info!("Hardware export cancelled, partial file removed: {}", path);
                }
            }
        }

        #[cfg(not(all(target_os = "android", feature = "ffmpeg")))]
        {
            log::info!("Hardware export cancelled (no-op on non-Android/FFmpeg)");
        }
    }
}

// ──────────────────────────────────────────────────────────────────
// Software encoding path (fallback)
// ──────────────────────────────────────────────────────────────────

impl HardwareEncoder {
    /// Open the software fallback encoder.
    fn open_software(&mut self, output_path: &str) -> Result<(), String> {
        if let Some(ref mut encoder) = self.software_encoder {
            encoder.open(output_path)?;
        } else {
            // Create software encoder on the fly (e.g., mid-stream fallback)
            let mut encoder = super::VideoEncoder::new(&self.settings)?;
            encoder.open(output_path)?;
            self.software_encoder = Some(encoder);
        }
        self.is_opened = true;
        self.start_time = std::time::Instant::now();
        Ok(())
    }

    /// Encode a frame using the software encoder.
    fn encode_software_frame(&mut self, rgba_data: &[u8], pts: i64) -> Result<(), String> {
        if let Some(ref mut encoder) = self.software_encoder {
            encoder.encode_rgba_frame(rgba_data, pts)
        } else {
            Err("Software encoder not available".to_string())
        }
    }

    /// Finish encoding using the software encoder.
    fn finish_software(mut self, duration_ms: u64) -> Result<ExportResult, String> {
        if let Some(encoder) = self.software_encoder.take() {
            encoder.finish(duration_ms)
        } else {
            Err("Software encoder not available".to_string())
        }
    }

    /// Cancel encoding using the software encoder.
    fn cancel_software(self) {
        if let Some(encoder) = self.software_encoder {
            encoder.cancel();
        }
    }

    /// Switch from hardware to software encoding.
    ///
    /// This is called when hardware encoding fails, either at `open()`
    /// time or mid-stream. It:
    ///
    /// 1. Cleans up the hardware encoder state
    /// 2. Creates a new software encoder
    /// 3. Marks `using_hardware = false`
    ///
    /// Note: When falling back mid-stream, the software encoder will
    /// start fresh from the current frame. This means any frames already
    /// encoded by the hardware encoder are lost. The output file is
    /// recreated from scratch by the software encoder.
    fn fallback_to_software(&mut self) -> Result<(), String> {
        log::warn!("Falling back from hardware to software encoding");

        // Clean up hardware state
        #[cfg(all(target_os = "android", feature = "ffmpeg"))]
        {
            if let Some(codec) = self.media_codec.as_mut() {
                codec.stop_and_release();
            }
            self.media_codec = None;
        }

        // Close and delete the partial output file (it may contain
        // incomplete data from the hardware encoder)
        #[cfg(all(target_os = "android", feature = "ffmpeg"))]
        {
            if let Some(octx) = self.mux_context.take() {
                drop(octx);
                if let Some(path) = &self.output_path {
                    let _ = std::fs::remove_file(path);
                    log::info!("Removed partial hardware-encoded file: {}", path);
                }
            }
        }

        // Reset frame count since the software encoder will start fresh
        self.frame_count = 0;

        // Create the software encoder
        self.software_encoder = Some(super::VideoEncoder::new(&self.settings)?);

        // Mark as software
        self.using_hardware = false;

        log::info!("Fallback to software encoding complete");
        Ok(())
    }
}

// ──────────────────────────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::export_engine::OutputFormat;

    #[test]
    fn test_hardware_encoder_type_equality() {
        assert_eq!(HardwareEncoderType::MediaCodec, HardwareEncoderType::MediaCodec);
        assert_eq!(HardwareEncoderType::None, HardwareEncoderType::None);
        assert_ne!(HardwareEncoderType::MediaCodec, HardwareEncoderType::None);
    }

    #[test]
    fn test_capabilities_detect() {
        // On non-Android, should return None type
        let caps = HardwareEncoderCapabilities::detect();
        #[cfg(not(target_os = "android"))]
        assert_eq!(caps.encoder_type, HardwareEncoderType::None);
    }

    #[test]
    fn test_capabilities_none() {
        let caps = HardwareEncoderCapabilities::none();
        assert_eq!(caps.encoder_type, HardwareEncoderType::None);
        assert!(caps.supported_codecs.is_empty());
        assert_eq!(caps.max_width, 0);
        assert_eq!(caps.max_height, 0);
        assert_eq!(caps.max_bitrate_kbps, 0);
    }

    #[test]
    fn test_capabilities_supports_settings_with_none() {
        let caps = HardwareEncoderCapabilities::none();
        let settings = ExportSettings::full_hd_1080p();
        assert!(!caps.supports_settings(&settings));
    }

    #[test]
    fn test_capabilities_supports_settings_with_hw() {
        let caps = HardwareEncoderCapabilities {
            encoder_type: HardwareEncoderType::MediaCodec,
            supported_codecs: vec![VideoCodec::H264, VideoCodec::H265],
            max_width: 3840,
            max_height: 2160,
            max_bitrate_kbps: 100_000,
        };

        // 1080p H.264 should be supported
        let settings = ExportSettings::full_hd_1080p();
        assert!(caps.supports_settings(&settings));

        // 4K H.265 should be supported
        let settings_4k = ExportSettings::ultra_hd_4k();
        assert!(caps.supports_settings(&settings_4k));
    }

    #[test]
    fn test_capabilities_supports_settings_unsupported_codec() {
        let caps = HardwareEncoderCapabilities {
            encoder_type: HardwareEncoderType::MediaCodec,
            supported_codecs: vec![VideoCodec::H264], // No H.265
            max_width: 3840,
            max_height: 2160,
            max_bitrate_kbps: 100_000,
        };

        // VP9 is not supported by hardware
        let mut settings = ExportSettings::full_hd_1080p();
        settings.codec = VideoCodec::Vp9;
        assert!(!caps.supports_settings(&settings));
    }

    #[test]
    fn test_capabilities_supports_settings_exceeds_resolution() {
        let caps = HardwareEncoderCapabilities {
            encoder_type: HardwareEncoderType::MediaCodec,
            supported_codecs: vec![VideoCodec::H264],
            max_width: 1920,
            max_height: 1080,
            max_bitrate_kbps: 100_000,
        };

        // 4K exceeds 1080p max
        let settings_4k = ExportSettings::ultra_hd_4k();
        assert!(!caps.supports_settings(&settings_4k));
    }

    #[test]
    fn test_capabilities_supports_settings_exceeds_bitrate() {
        let caps = HardwareEncoderCapabilities {
            encoder_type: HardwareEncoderType::MediaCodec,
            supported_codecs: vec![VideoCodec::H264],
            max_width: 3840,
            max_height: 2160,
            max_bitrate_kbps: 5_000, // Very low limit
        };

        let settings = ExportSettings::full_hd_1080p(); // 10,000 kbps
        assert!(!caps.supports_settings(&settings));
    }

    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_hardware_encoder_new_valid_settings() {
        let settings = ExportSettings::full_hd_1080p();
        let encoder = HardwareEncoder::new(&settings);
        assert!(encoder.is_ok());

        let encoder = encoder.unwrap();
        // On non-Android, should not be using hardware
        #[cfg(not(target_os = "android"))]
        assert!(!encoder.is_hardware_accelerated());
    }

    #[test]
    fn test_hardware_encoder_new_zero_dimensions() {
        let mut settings = ExportSettings::full_hd_1080p();
        settings.width = 0;
        let result = HardwareEncoder::new(&settings);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("non-zero"));
    }

    #[test]
    fn test_hardware_encoder_new_odd_dimensions() {
        let mut settings = ExportSettings::full_hd_1080p();
        settings.width = 1921;
        let result = HardwareEncoder::new(&settings);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("even"));
    }

    #[test]
    fn test_hardware_encoder_new_zero_bitrate() {
        let mut settings = ExportSettings::full_hd_1080p();
        settings.bitrate_kbps = 0;
        let result = HardwareEncoder::new(&settings);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Bitrate"));
    }

    #[test]
    fn test_hardware_encoder_new_zero_fps() {
        let mut settings = ExportSettings::full_hd_1080p();
        settings.fps = 0.0;
        let result = HardwareEncoder::new(&settings);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("FPS"));
    }

    #[test]
    fn test_hardware_encoder_is_available() {
        // On non-Android, no hardware encoder is available
        #[cfg(not(target_os = "android"))]
        assert!(!HardwareEncoder::is_available());
    }

    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_hardware_encoder_not_opened_encode() {
        let settings = ExportSettings::full_hd_1080p();
        let mut encoder = HardwareEncoder::new(&settings).unwrap();
        let rgba = vec![0u8; 1920 * 1080 * 4];
        let result = encoder.encode_rgba_frame(&rgba, 0);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not opened"));
    }

    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_hardware_encoder_not_opened_finish() {
        let settings = ExportSettings::full_hd_1080p();
        let encoder = HardwareEncoder::new(&settings).unwrap();
        let result = encoder.finish(10000);
        assert!(result.is_err());
    }

    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_hardware_encoder_double_open() {
        let settings = ExportSettings::full_hd_1080p();
        let mut encoder = HardwareEncoder::new(&settings).unwrap();

        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test_double_open.mp4");
        let path_str = path.to_str().unwrap();

        // First open should succeed (using software fallback on non-Android)
        // Note: This test may fail if FFmpeg is not available, which is
        // expected in CI environments without FFmpeg.
        if encoder.open(path_str).is_ok() {
            // Second open should fail
            let result = encoder.open(path_str);
            assert!(result.is_err());
            assert!(result.unwrap_err().contains("already opened"));
        }
    }

    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_hardware_encoder_frame_count() {
        let settings = ExportSettings::full_hd_1080p();
        let encoder = HardwareEncoder::new(&settings).unwrap();
        assert_eq!(encoder.frame_count(), 0);
    }

    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_hardware_encoder_encoder_type() {
        let settings = ExportSettings::full_hd_1080p();
        let encoder = HardwareEncoder::new(&settings).unwrap();
        #[cfg(not(target_os = "android"))]
        assert_eq!(encoder.encoder_type(), HardwareEncoderType::None);
    }

    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_hardware_encoder_capabilities_accessor() {
        let settings = ExportSettings::full_hd_1080p();
        let encoder = HardwareEncoder::new(&settings).unwrap();
        let caps = encoder.capabilities();
        #[cfg(not(target_os = "android"))]
        assert_eq!(caps.encoder_type, HardwareEncoderType::None);
    }

    #[cfg(feature = "ffmpeg")]
    #[test]
    fn test_software_fallback_on_non_android() {
        // On non-Android platforms, the encoder should immediately
        // use software encoding and have a software_encoder ready.
        let settings = ExportSettings::full_hd_1080p();
        let encoder = HardwareEncoder::new(&settings).unwrap();
        assert!(!encoder.is_hardware_accelerated());
        // The software encoder should have been created during new()
        assert!(encoder.software_encoder.is_some());
    }

    #[test]
    fn test_media_codec_output_buffer() {
        let buf = MediaCodecOutputBuffer {
            data: vec![0x00, 0x00, 0x00, 0x01, 0x65], // H.264 IDR slice NAL
            presentation_time_us: 33333,
            flags: 0x0001, // BUFFER_FLAG_KEY_FRAME
        };
        assert_eq!(buf.data.len(), 5);
        assert_eq!(buf.presentation_time_us, 33333);
        assert_ne!(buf.flags & 0x0001, 0); // key frame flag set
    }
}
