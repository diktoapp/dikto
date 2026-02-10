uniffi::setup_scaffolding!();

pub mod audio;
pub mod config;
pub mod engine;
pub mod models;
pub mod transcribe;
pub mod vad;

use audio::{AudioCapture, AudioCaptureConfig, AudioError};
use config::DiktoConfig;
use engine::{AsrEngine, AsrSession, LoadedEngine};
use models::{ModelBackend, ModelError};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use thiserror::Error;
use tracing::{debug, info, warn};
use transcribe::{TranscribeConfig, TranscribeError};
use vad::{VadConfig, VadError, VadEvent, VadProcessor};

/// Old Whisper model names (v1) that should be auto-migrated to Parakeet.
const OLD_WHISPER_MODEL_NAMES: &[&str] = &["tiny.en", "base.en", "small.en", "medium.en"];

/// Errors from the Dikto engine.
#[derive(Debug, Error, uniffi::Error)]
pub enum DiktoError {
    #[error("Audio error: {0}")]
    Audio(String),
    #[error("VAD error: {0}")]
    Vad(String),
    #[error("Transcription error: {0}")]
    Transcribe(String),
    #[error("Model error: {0}")]
    Model(String),
    #[error("No model loaded. Run: dikto --setup")]
    NoModel,
    #[error("Already recording")]
    AlreadyRecording,
    #[error("Config error: {0}")]
    Config(String),
}

impl From<AudioError> for DiktoError {
    fn from(e: AudioError) -> Self {
        DiktoError::Audio(e.to_string())
    }
}
impl From<VadError> for DiktoError {
    fn from(e: VadError) -> Self {
        DiktoError::Vad(e.to_string())
    }
}
impl From<TranscribeError> for DiktoError {
    fn from(e: TranscribeError) -> Self {
        DiktoError::Transcribe(e.to_string())
    }
}
impl From<ModelError> for DiktoError {
    fn from(e: ModelError) -> Self {
        DiktoError::Model(e.to_string())
    }
}

/// Recording state enum.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum RecordingState {
    Listening,
    Processing,
    Done { text: String },
    Error { message: String },
}

/// Callbacks for transcription events.
#[uniffi::export(with_foreign)]
pub trait TranscriptionCallback: Send + Sync {
    fn on_partial(&self, text: String);
    fn on_final_segment(&self, text: String);
    fn on_silence(&self);
    fn on_error(&self, error: String);
    fn on_state_change(&self, state: RecordingState);
}

/// Callbacks for model download progress.
#[uniffi::export(with_foreign)]
pub trait DownloadProgressCallback: Send + Sync {
    fn on_progress(&self, bytes_downloaded: u64, total_bytes: u64);
    fn on_complete(&self, model_name: String);
    fn on_error(&self, error: String);
}

/// Configuration for a listening session.
#[derive(Debug, Clone, uniffi::Record)]
pub struct ListenConfig {
    pub language: String,
    pub max_duration: u32,
    pub silence_duration_ms: u32,
    pub speech_threshold: f32,
}

impl Default for ListenConfig {
    fn default() -> Self {
        Self {
            language: "en".to_string(),
            max_duration: 30,
            silence_duration_ms: 1500,
            speech_threshold: 0.35,
        }
    }
}

impl From<&DiktoConfig> for ListenConfig {
    fn from(cfg: &DiktoConfig) -> Self {
        Self {
            language: cfg.language.clone(),
            max_duration: cfg.max_duration,
            silence_duration_ms: cfg.silence_duration_ms,
            speech_threshold: cfg.speech_threshold,
        }
    }
}

/// Handle to stop a running recording session.
#[derive(uniffi::Object)]
pub struct SessionHandle {
    stop_flag: Arc<AtomicBool>,
}

impl SessionHandle {
    /// Create a SessionHandle for testing (not used by production code).
    pub fn new_for_test() -> Self {
        Self {
            stop_flag: Arc::new(AtomicBool::new(false)),
        }
    }
}

#[uniffi::export]
impl SessionHandle {
    /// Stop the recording session.
    pub fn stop(&self) {
        self.stop_flag.store(true, Ordering::Release);
    }

    /// Check if the session is still active.
    pub fn is_active(&self) -> bool {
        !self.stop_flag.load(Ordering::Acquire)
    }
}

/// Owned model info record for FFI.
#[derive(Debug, Clone, uniffi::Record)]
pub struct ModelInfoRecord {
    pub name: String,
    pub size_mb: u32,
    pub description: String,
    pub is_downloaded: bool,
    pub backend: String,
}

/// Language info record for FFI.
#[derive(Debug, Clone, uniffi::Record)]
pub struct LanguageInfo {
    pub code: String,
    pub name: String,
}

/// Inner state of DiktoEngine, behind a Mutex for UniFFI compatibility.
struct DiktoEngineInner {
    /// Shared engine holder — None when no model is loaded in RAM.
    /// Arc allows sharing with pipeline threads for lazy loading.
    engine: Arc<Mutex<Option<LoadedEngine>>>,
    config: DiktoConfig,
    recording: Arc<AtomicBool>,
}

/// The main Dikto engine. Models are loaded lazily into RAM on first recording.
#[derive(uniffi::Object)]
pub struct DiktoEngine {
    inner: Mutex<DiktoEngineInner>,
}

#[uniffi::export]
impl DiktoEngine {
    /// Create a new DiktoEngine. Does NOT load any model into RAM.
    /// Auto-migrates old v1 Whisper model configs to Parakeet.
    #[uniffi::constructor]
    #[allow(clippy::new_without_default)]
    pub fn new() -> Self {
        let mut config = config::load_config();

        // Auto-migrate old v1 Whisper model names to Parakeet default
        if OLD_WHISPER_MODEL_NAMES.contains(&config.model_name.as_str()) {
            warn!(
                "Migrating config from old Whisper model '{}' to Parakeet default",
                config.model_name
            );
            config.model_name = config::default_model_name();
            if let Err(e) = config::save_config(&config) {
                warn!("Failed to save migrated config: {e}");
            }
        }

        Self {
            inner: Mutex::new(DiktoEngineInner {
                engine: Arc::new(Mutex::new(None)),
                config,
                recording: Arc::new(AtomicBool::new(false)),
            }),
        }
    }

    /// Explicitly load the configured model into RAM.
    /// Optional — start_listening() will lazy-load if needed.
    pub fn load_model(&self) -> Result<(), DiktoError> {
        let inner = self
            .inner
            .lock()
            .map_err(|e| DiktoError::Config(format!("Lock poisoned: {e}")))?;
        let model_name = inner.config.model_name.clone();
        let model_info = models::find_model(&model_name).ok_or(DiktoError::NoModel)?;
        let path = models::model_path(&model_name).ok_or(DiktoError::NoModel)?;

        if !models::is_model_downloaded(&model_name) {
            return Err(DiktoError::NoModel);
        }

        let asr = AsrEngine::load(model_info.backend, &path)?;
        *inner
            .engine
            .lock()
            .map_err(|e| DiktoError::Config(format!("Lock poisoned: {e}")))? = Some(LoadedEngine {
            model_name: model_name.clone(),
            engine: asr,
        });
        info!("Model '{}' loaded and ready", model_name);
        Ok(())
    }

    /// Unload the current model from RAM, freeing memory.
    pub fn unload_model(&self) {
        let Ok(inner) = self.inner.lock() else { return };
        let was_loaded = inner
            .engine
            .lock()
            .ok()
            .and_then(|mut g| g.take())
            .is_some();
        if was_loaded {
            info!("Model unloaded from RAM");
        }
    }

    /// Switch to a different model. Unloads the current model from RAM.
    /// The new model will be loaded lazily on next recording.
    pub fn switch_model(&self, model_name: String) -> Result<(), DiktoError> {
        let mut inner = self
            .inner
            .lock()
            .map_err(|e| DiktoError::Config(format!("Lock poisoned: {e}")))?;

        if inner.recording.load(Ordering::Acquire) {
            return Err(DiktoError::AlreadyRecording);
        }

        // Verify model exists and is downloaded
        let _ = models::find_model(&model_name).ok_or(DiktoError::NoModel)?;
        if !models::is_model_downloaded(&model_name) {
            return Err(DiktoError::NoModel);
        }

        // Unload old model from RAM
        if let Ok(mut guard) = inner.engine.lock() {
            *guard = None;
        }

        // Save new model choice
        inner.config.model_name = model_name.clone();
        config::save_config(&inner.config).map_err(|e| DiktoError::Config(e.to_string()))?;
        info!(
            "Switched to model '{}' (will load on next recording)",
            model_name
        );
        Ok(())
    }

    /// Start listening and transcribing. Returns a handle to stop the session.
    /// Lazy-loads the model into RAM if not already loaded.
    /// The final result is delivered via the callback's on_state_change(Done { text }).
    pub fn start_listening(
        &self,
        listen_config: ListenConfig,
        callback: Arc<dyn TranscriptionCallback>,
    ) -> Result<Arc<SessionHandle>, DiktoError> {
        let inner = self
            .inner
            .lock()
            .map_err(|e| DiktoError::Config(format!("Lock poisoned: {e}")))?;

        if inner.recording.load(Ordering::Acquire) {
            return Err(DiktoError::AlreadyRecording);
        }

        // Verify model is available on disk
        let model_name = inner.config.model_name.clone();
        let model_info = models::find_model(&model_name).ok_or(DiktoError::NoModel)?;
        if !models::is_model_downloaded(&model_name) {
            return Err(DiktoError::NoModel);
        }

        let engine_holder = inner.engine.clone();
        let backend = model_info.backend;
        let model_path = models::model_path(&model_name).ok_or(DiktoError::NoModel)?;

        let stop_flag = Arc::new(AtomicBool::new(false));
        let handle = Arc::new(SessionHandle {
            stop_flag: stop_flag.clone(),
        });

        let recording = inner.recording.clone();
        recording.store(true, Ordering::Release);

        let max_duration = listen_config.max_duration;
        let silence_duration_ms = listen_config.silence_duration_ms;
        let speech_threshold = listen_config.speech_threshold;
        let language = listen_config.language.clone();

        drop(inner); // Release outer lock before spawning

        std::thread::spawn(move || {
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                // Lazy-load model if needed
                let needs_load = {
                    let guard = engine_holder
                        .lock()
                        .map_err(|e| DiktoError::Config(format!("Lock poisoned: {e}")))?;
                    !matches!(&*guard, Some(loaded) if loaded.model_name == model_name)
                };

                if needs_load {
                    callback.on_state_change(RecordingState::Processing);
                    callback.on_partial("Loading model...".to_string());
                    debug!("Lazy-loading model '{}'...", model_name);

                    match AsrEngine::load(backend, &model_path) {
                        Ok(asr) => {
                            let mut guard = engine_holder
                                .lock()
                                .map_err(|e| DiktoError::Config(format!("Lock poisoned: {e}")))?;
                            *guard = Some(LoadedEngine {
                                model_name: model_name.clone(),
                                engine: asr,
                            });
                            debug!("Model '{}' loaded into RAM", model_name);
                        }
                        Err(e) => {
                            recording.store(false, Ordering::Release);
                            callback.on_state_change(RecordingState::Error {
                                message: format!("Failed to load model: {e}"),
                            });
                            return Ok(());
                        }
                    }
                }

                // Create transcription session
                let transcribe_config = TranscribeConfig { language };
                let session = {
                    let guard = engine_holder
                        .lock()
                        .map_err(|e| DiktoError::Config(format!("Lock poisoned: {e}")))?;
                    let loaded = guard.as_ref().ok_or(DiktoError::NoModel)?;
                    loaded.engine.create_session(transcribe_config)
                };

                let result = run_pipeline(
                    session,
                    &engine_holder,
                    stop_flag,
                    callback.clone(),
                    max_duration,
                    silence_duration_ms,
                    speech_threshold,
                );

                recording.store(false, Ordering::Release);

                match &result {
                    Ok(text) => {
                        debug!("pipeline done, text_len={}", text.len());
                        callback.on_state_change(RecordingState::Done { text: text.clone() });
                    }
                    Err(e) => {
                        warn!("pipeline error: {e}");
                        callback.on_state_change(RecordingState::Error {
                            message: e.to_string(),
                        });
                    }
                }

                Ok::<(), DiktoError>(())
            }));

            if let Err(_panic) = result {
                recording.store(false, Ordering::Release);
                callback.on_state_change(RecordingState::Error {
                    message: "Internal error (thread panic)".to_string(),
                });
            }
        });

        Ok(handle)
    }

    /// Get a copy of the current config.
    pub fn get_config(&self) -> DiktoConfig {
        match self.inner.lock() {
            Ok(g) => g.config.clone(),
            Err(e) => {
                warn!("get_config: lock poisoned ({e}), returning defaults");
                DiktoConfig::default()
            }
        }
    }

    /// Update config and save.
    pub fn update_config(&self, config: DiktoConfig) -> Result<(), DiktoError> {
        let mut inner = self
            .inner
            .lock()
            .map_err(|e| DiktoError::Config(format!("Lock poisoned: {e}")))?;
        config::save_config(&config).map_err(|e| DiktoError::Config(e.to_string()))?;
        inner.config = config;
        Ok(())
    }

    /// List available models with download status.
    pub fn list_models(&self) -> Vec<ModelInfoRecord> {
        models::list_models()
            .into_iter()
            .map(|(m, downloaded)| ModelInfoRecord {
                name: m.name.to_string(),
                size_mb: m.size_mb,
                description: m.description.to_string(),
                is_downloaded: downloaded,
                backend: match m.backend {
                    ModelBackend::Parakeet => "Parakeet".to_string(),
                    ModelBackend::Whisper => "Whisper".to_string(),
                },
            })
            .collect()
    }

    /// Download a model with progress reporting via callback.
    pub fn download_model(
        &self,
        model_name: String,
        callback: Arc<dyn DownloadProgressCallback>,
    ) -> Result<(), DiktoError> {
        // Verify model exists
        let _ = models::find_model(&model_name)
            .ok_or_else(|| DiktoError::Model(format!("Unknown model: {model_name}")))?;

        let name = model_name.clone();
        std::thread::spawn(move || {
            let rt = match tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
            {
                Ok(rt) => rt,
                Err(e) => {
                    callback.on_error(format!("Failed to create runtime: {e}"));
                    return;
                }
            };

            rt.block_on(async {
                let cb = callback.clone();
                match models::download_model(&name, move |downloaded, total| {
                    cb.on_progress(downloaded, total);
                })
                .await
                {
                    Ok(_) => callback.on_complete(name),
                    Err(e) => callback.on_error(e.to_string()),
                }
            });
        });

        Ok(())
    }

    /// Get available languages for the currently configured model.
    pub fn available_languages(&self) -> Vec<LanguageInfo> {
        let Ok(inner) = self.inner.lock() else {
            return vec![LanguageInfo {
                code: "en".to_string(),
                name: "English".to_string(),
            }];
        };
        let model_name = &inner.config.model_name;

        match models::find_model(model_name) {
            Some(m) if m.backend == ModelBackend::Parakeet && model_name.contains("-v3") => {
                parakeet_v3_languages()
            }
            Some(m) if m.backend == ModelBackend::Parakeet => vec![LanguageInfo {
                code: "en".to_string(),
                name: "English".to_string(),
            }],
            Some(m) if m.backend == ModelBackend::Whisper => whisper_languages(),
            _ => vec![LanguageInfo {
                code: "en".to_string(),
                name: "English".to_string(),
            }],
        }
    }

    /// Check if the configured model's files are downloaded (available on disk).
    /// This does NOT mean the model is loaded into RAM.
    pub fn is_model_available(&self) -> bool {
        let Ok(inner) = self.inner.lock() else {
            return false;
        };
        models::is_model_downloaded(&inner.config.model_name)
    }

    /// Check if a model is currently loaded in RAM.
    pub fn is_model_loaded(&self) -> bool {
        let Ok(inner) = self.inner.lock() else {
            return false;
        };
        let Ok(engine_guard) = inner.engine.lock() else {
            return false;
        };
        engine_guard.is_some()
    }

    /// Check if currently recording.
    pub fn is_recording(&self) -> bool {
        match self.inner.lock() {
            Ok(g) => g.recording.load(Ordering::Acquire),
            Err(e) => {
                warn!("is_recording: lock poisoned ({e}), returning false");
                false
            }
        }
    }

    /// Get the models directory path (for debugging).
    pub fn models_dir(&self) -> String {
        config::models_dir().to_string_lossy().to_string()
    }
}

/// The main recording + transcription pipeline, runs on a background thread.
fn run_pipeline(
    mut session: AsrSession,
    engine: &Arc<Mutex<Option<LoadedEngine>>>,
    stop_flag: Arc<AtomicBool>,
    callback: Arc<dyn TranscriptionCallback>,
    max_duration: u32,
    silence_duration_ms: u32,
    speech_threshold: f32,
) -> Result<String, DiktoError> {
    callback.on_state_change(RecordingState::Listening);

    // Start audio capture
    let mut capture = AudioCapture::start(AudioCaptureConfig::default())?;

    // Initialize VAD
    let vad_config = VadConfig {
        speech_threshold,
        silence_duration_ms,
        ..Default::default()
    };
    let mut vad = VadProcessor::new(vad_config)?;
    let chunk_size = vad.chunk_size();

    let start_time = std::time::Instant::now();
    let max_dur = std::time::Duration::from_secs(max_duration as u64);

    let mut vad_buffer: Vec<f32> = Vec::new();
    let mut speech_detected = false;
    // Buffer ~1s of pre-speech audio so we don't lose the start of speech
    let pre_speech_max = 16000usize; // 1 second at 16kHz
    let mut pre_speech_buffer: Vec<f32> = Vec::new();
    // Throttle overlay updates to every ~500ms
    let mut last_partial_time = std::time::Instant::now();

    loop {
        // Check stop conditions
        if stop_flag.load(Ordering::Acquire) {
            info!("Stop requested");
            break;
        }
        if start_time.elapsed() >= max_dur {
            info!("Max duration reached");
            break;
        }

        // Read samples from mic
        let samples = capture.read_samples();
        if samples.is_empty() {
            std::thread::sleep(std::time::Duration::from_millis(10));
            continue;
        }

        // Feed to VAD in chunks
        vad_buffer.extend_from_slice(&samples);

        while vad_buffer.len() >= chunk_size {
            let chunk: Vec<f32> = vad_buffer.drain(..chunk_size).collect();

            match vad.process_chunk(&chunk)? {
                VadEvent::SpeechStart => {
                    speech_detected = true;
                    debug!(
                        "Speech detected, feeding {} pre-speech samples",
                        pre_speech_buffer.len()
                    );
                    // Feed buffered pre-speech audio so transcription captures the start
                    if !pre_speech_buffer.is_empty() {
                        session.feed_samples(&pre_speech_buffer);
                        pre_speech_buffer.clear();
                    }
                }
                VadEvent::SpeechEnd => {
                    if speech_detected {
                        callback.on_silence();
                        info!("Speech ended (silence detected)");

                        // Flush remaining audio — batch inference happens here
                        callback.on_state_change(RecordingState::Processing);
                        let final_segments = session.flush(engine)?;
                        let text = final_segments
                            .iter()
                            .map(|s| s.text.as_str())
                            .collect::<Vec<_>>()
                            .join(" ");

                        for seg in &final_segments {
                            callback.on_final_segment(seg.text.clone());
                        }

                        capture.stop();
                        return Ok(text);
                    }
                }
                VadEvent::SpeechContinue | VadEvent::Silence => {}
            }
        }

        // Feed audio to transcription buffer or buffer pre-speech audio
        if speech_detected {
            session.feed_samples(&samples);

            // Send "Recording..." status to overlay (throttled)
            if last_partial_time.elapsed() >= std::time::Duration::from_millis(500) {
                let duration = session.buffer_duration_secs();
                callback.on_partial(format!("Recording... ({duration:.1}s)"));
                last_partial_time = std::time::Instant::now();
            }
        } else {
            // Ring-buffer pre-speech audio (keep last ~1s)
            pre_speech_buffer.extend_from_slice(&samples);
            if pre_speech_buffer.len() > pre_speech_max {
                let excess = pre_speech_buffer.len() - pre_speech_max;
                pre_speech_buffer.drain(..excess);
            }
        }
    }

    // Flush on stop
    callback.on_state_change(RecordingState::Processing);
    let final_segments = session.flush(engine)?;
    let text = final_segments
        .iter()
        .map(|s| s.text.as_str())
        .collect::<Vec<_>>()
        .join(" ");

    for seg in &final_segments {
        callback.on_final_segment(seg.text.clone());
    }

    capture.stop();
    Ok(text)
}

/// Parakeet TDT v3 supported languages (25 European languages).
pub fn parakeet_v3_languages() -> Vec<LanguageInfo> {
    [
        ("en", "English"),
        ("de", "German"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("ru", "Russian"),
        ("uk", "Ukrainian"),
        ("cs", "Czech"),
        ("ro", "Romanian"),
        ("hu", "Hungarian"),
        ("el", "Greek"),
        ("bg", "Bulgarian"),
        ("hr", "Croatian"),
        ("sk", "Slovak"),
        ("sl", "Slovenian"),
        ("lt", "Lithuanian"),
        ("lv", "Latvian"),
        ("et", "Estonian"),
        ("fi", "Finnish"),
        ("da", "Danish"),
        ("sv", "Swedish"),
        ("no", "Norwegian"),
    ]
    .iter()
    .map(|(code, name)| LanguageInfo {
        code: code.to_string(),
        name: name.to_string(),
    })
    .collect()
}

/// Top Whisper-supported languages.
pub fn whisper_languages() -> Vec<LanguageInfo> {
    [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("zh", "Chinese"),
        ("de", "German"),
        ("es", "Spanish"),
        ("ru", "Russian"),
        ("ko", "Korean"),
        ("fr", "French"),
        ("ja", "Japanese"),
        ("pt", "Portuguese"),
        ("tr", "Turkish"),
        ("pl", "Polish"),
        ("ca", "Catalan"),
        ("nl", "Dutch"),
        ("ar", "Arabic"),
        ("sv", "Swedish"),
        ("it", "Italian"),
        ("id", "Indonesian"),
        ("hi", "Hindi"),
        ("fi", "Finnish"),
        ("vi", "Vietnamese"),
        ("he", "Hebrew"),
        ("uk", "Ukrainian"),
        ("el", "Greek"),
        ("ms", "Malay"),
        ("cs", "Czech"),
        ("ro", "Romanian"),
        ("da", "Danish"),
        ("hu", "Hungarian"),
        ("ta", "Tamil"),
        ("no", "Norwegian"),
        ("th", "Thai"),
    ]
    .iter()
    .map(|(code, name)| LanguageInfo {
        code: code.to_string(),
        name: name.to_string(),
    })
    .collect()
}
