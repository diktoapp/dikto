uniffi::setup_scaffolding!();

pub mod audio;
pub mod clipboard;
pub mod config;
pub mod models;
pub mod transcribe;
pub mod vad;

use audio::{AudioCapture, AudioCaptureConfig, AudioError};
use config::SottoConfig;
use models::ModelError;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use thiserror::Error;
use tracing::{debug, info, warn};
use transcribe::{ParakeetEngine, TranscribeConfig, TranscribeError};
use vad::{VadConfig, VadError, VadEvent, VadProcessor};

/// Old Whisper model names that should be auto-migrated to Parakeet.
const WHISPER_MODEL_NAMES: &[&str] = &["tiny.en", "base.en", "small.en", "medium.en"];

/// Errors from the Sotto engine.
#[derive(Debug, Error, uniffi::Error)]
pub enum SottoError {
    #[error("Audio error: {0}")]
    Audio(String),
    #[error("VAD error: {0}")]
    Vad(String),
    #[error("Transcription error: {0}")]
    Transcribe(String),
    #[error("Model error: {0}")]
    Model(String),
    #[error("No model loaded. Run: sotto --setup")]
    NoModel,
    #[error("Already recording")]
    AlreadyRecording,
    #[error("Config error: {0}")]
    Config(String),
}

impl From<AudioError> for SottoError {
    fn from(e: AudioError) -> Self {
        SottoError::Audio(e.to_string())
    }
}
impl From<VadError> for SottoError {
    fn from(e: VadError) -> Self {
        SottoError::Vad(e.to_string())
    }
}
impl From<TranscribeError> for SottoError {
    fn from(e: TranscribeError) -> Self {
        SottoError::Transcribe(e.to_string())
    }
}
impl From<ModelError> for SottoError {
    fn from(e: ModelError) -> Self {
        SottoError::Model(e.to_string())
    }
}

/// Recording state enum.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum RecordingState {
    Idle,
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

impl From<&SottoConfig> for ListenConfig {
    fn from(cfg: &SottoConfig) -> Self {
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

#[uniffi::export]
impl SessionHandle {
    /// Stop the recording session.
    pub fn stop(&self) {
        self.stop_flag.store(true, Ordering::Relaxed);
    }

    /// Check if the session is still active.
    pub fn is_active(&self) -> bool {
        !self.stop_flag.load(Ordering::Relaxed)
    }
}

/// Owned model info record for FFI.
#[derive(Debug, Clone, uniffi::Record)]
pub struct ModelInfoRecord {
    pub name: String,
    pub size_mb: u32,
    pub description: String,
    pub is_downloaded: bool,
}

/// Inner state of SottoEngine, behind a Mutex for UniFFI compatibility.
struct SottoEngineInner {
    engine: Option<Arc<Mutex<ParakeetEngine>>>,
    config: SottoConfig,
    recording: Arc<AtomicBool>,
}

/// The main Sotto engine. Keeps the model loaded in memory.
#[derive(uniffi::Object)]
pub struct SottoEngine {
    inner: Mutex<SottoEngineInner>,
}

#[uniffi::export]
impl SottoEngine {
    /// Create a new SottoEngine. Does NOT load the model yet.
    /// Auto-migrates old Whisper model configs to Parakeet.
    #[uniffi::constructor]
    pub fn new() -> Self {
        let mut config = config::load_config();

        // Auto-migrate old Whisper model names to Parakeet default
        if WHISPER_MODEL_NAMES.contains(&config.model_name.as_str()) {
            warn!(
                "Migrating config from Whisper model '{}' to Parakeet default",
                config.model_name
            );
            config.model_name = config::default_model_name();
            if let Err(e) = config::save_config(&config) {
                warn!("Failed to save migrated config: {e}");
            }
        }

        Self {
            inner: Mutex::new(SottoEngineInner {
                engine: None,
                config,
                recording: Arc::new(AtomicBool::new(false)),
            }),
        }
    }

    /// Load the configured model. Call this once at startup.
    pub fn load_model(&self) -> Result<(), SottoError> {
        let mut inner = self.inner.lock().unwrap();
        let model_name = inner.config.model_name.clone();
        let path = models::model_path(&model_name).ok_or(SottoError::NoModel)?;

        if !models::is_model_downloaded(&model_name) {
            return Err(SottoError::NoModel);
        }

        let engine = ParakeetEngine::load(&path)?;
        inner.engine = Some(Arc::new(Mutex::new(engine)));
        info!("Model '{}' loaded and ready", model_name);
        Ok(())
    }

    /// Switch to a different model (hot-swap).
    pub fn switch_model(&self, model_name: String) -> Result<(), SottoError> {
        let mut inner = self.inner.lock().unwrap();
        let path = models::model_path(&model_name).ok_or(SottoError::NoModel)?;
        if !models::is_model_downloaded(&model_name) {
            return Err(SottoError::NoModel);
        }

        let engine = ParakeetEngine::load(&path)?;
        inner.engine = Some(Arc::new(Mutex::new(engine)));
        inner.config.model_name = model_name.clone();
        config::save_config(&inner.config).map_err(|e| SottoError::Config(e.to_string()))?;
        info!("Switched to model '{}'", model_name);
        Ok(())
    }

    /// Start listening and transcribing. Returns a handle to stop the session.
    /// The final result is delivered via the callback's on_state_change(Done { text }).
    pub fn start_listening(
        &self,
        listen_config: ListenConfig,
        callback: Arc<dyn TranscriptionCallback>,
    ) -> Result<Arc<SessionHandle>, SottoError> {
        let inner = self.inner.lock().unwrap();

        if inner.recording.load(Ordering::Relaxed) {
            return Err(SottoError::AlreadyRecording);
        }

        let engine = inner.engine.as_ref().ok_or(SottoError::NoModel)?.clone();

        let transcribe_config = TranscribeConfig {
            language: listen_config.language.clone(),
        };

        let session = engine
            .lock()
            .map_err(|e| SottoError::Transcribe(format!("Lock poisoned: {e}")))?
            .create_session(transcribe_config);

        let stop_flag = Arc::new(AtomicBool::new(false));
        let handle = Arc::new(SessionHandle {
            stop_flag: stop_flag.clone(),
        });

        let recording = inner.recording.clone();
        recording.store(true, Ordering::Relaxed);

        let max_duration = listen_config.max_duration;
        let silence_duration_ms = listen_config.silence_duration_ms;
        let speech_threshold = listen_config.speech_threshold;

        std::thread::spawn(move || {
            let result = run_pipeline(
                session,
                &engine,
                stop_flag,
                recording.clone(),
                callback.clone(),
                max_duration,
                silence_duration_ms,
                speech_threshold,
            );

            recording.store(false, Ordering::Relaxed);

            match &result {
                Ok(text) => {
                    eprintln!("[sotto] pipeline done, text='{}' (len={})", text.chars().take(80).collect::<String>(), text.len());
                    callback.on_state_change(RecordingState::Done {
                        text: text.clone(),
                    });
                    eprintln!("[sotto] Done callback fired");
                }
                Err(e) => {
                    eprintln!("[sotto] pipeline error: {e}");
                    callback.on_state_change(RecordingState::Error {
                        message: e.to_string(),
                    });
                }
            }
        });

        Ok(handle)
    }

    /// Get a copy of the current config.
    pub fn get_config(&self) -> SottoConfig {
        self.inner.lock().unwrap().config.clone()
    }

    /// Update config and save.
    pub fn update_config(&self, config: SottoConfig) -> Result<(), SottoError> {
        let mut inner = self.inner.lock().unwrap();
        config::save_config(&config).map_err(|e| SottoError::Config(e.to_string()))?;
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
            })
            .collect()
    }

    /// Check if currently recording.
    pub fn is_recording(&self) -> bool {
        self.inner.lock().unwrap().recording.load(Ordering::Relaxed)
    }

    /// Get the models directory path (for debugging).
    pub fn models_dir(&self) -> String {
        config::models_dir().to_string_lossy().to_string()
    }
}

/// The main recording + transcription pipeline, runs on a background thread.
fn run_pipeline(
    mut session: transcribe::TranscribeSession,
    engine: &Arc<Mutex<ParakeetEngine>>,
    stop_flag: Arc<AtomicBool>,
    _recording: Arc<AtomicBool>,
    callback: Arc<dyn TranscriptionCallback>,
    max_duration: u32,
    silence_duration_ms: u32,
    speech_threshold: f32,
) -> Result<String, SottoError> {
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
        if stop_flag.load(Ordering::Relaxed) {
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
                    debug!("Speech detected, feeding {} pre-speech samples", pre_speech_buffer.len());
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
                callback.on_partial(format!("Recording... ({:.1}s)", duration));
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
