use std::path::Path;
use std::sync::{Arc, Mutex};
use thiserror::Error;
use tracing::info;

use parakeet_rs::{ParakeetTDT, Transcriber};

#[derive(Debug, Error)]
pub enum TranscribeError {
    #[error("Failed to load model: {0}")]
    ModelLoad(String),
    #[error("Inference failed: {0}")]
    Inference(String),
    #[error("Model not loaded")]
    NotLoaded,
}

/// Configuration for transcription.
#[derive(Debug, Clone)]
pub struct TranscribeConfig {
    /// Language code (e.g., "en").
    pub language: String,
}

impl Default for TranscribeConfig {
    fn default() -> Self {
        Self {
            language: "en".to_string(),
        }
    }
}

/// A segment of transcribed text.
#[derive(Debug, Clone)]
pub struct TranscriptSegment {
    pub text: String,
    pub is_final: bool,
}

/// Parakeet TDT engine that keeps the model loaded in memory.
pub struct ParakeetEngine {
    model: ParakeetTDT,
}

// ParakeetTDT uses ort::Session internally which isn't Send/Sync by default.
// Safety: we only access it from one thread at a time via Mutex.
unsafe impl Send for ParakeetEngine {}
unsafe impl Sync for ParakeetEngine {}

impl ParakeetEngine {
    /// Load a Parakeet TDT model from a directory.
    /// The directory must contain encoder-model.onnx, decoder_joint-model.onnx, and vocab.txt.
    pub fn load(model_dir: &Path) -> Result<Self, TranscribeError> {
        info!("Loading Parakeet TDT model from {}", model_dir.display());

        let model = ParakeetTDT::from_pretrained(model_dir, None)
            .map_err(|e| TranscribeError::ModelLoad(e.to_string()))?;

        info!("Parakeet TDT model loaded successfully");

        Ok(Self { model })
    }

    /// Create a new transcription session.
    pub fn create_session(&self, _config: TranscribeConfig) -> TranscribeSession {
        TranscribeSession {
            audio_buffer: Vec::new(),
        }
    }

    /// Run batch inference on audio samples.
    /// Returns the transcribed text.
    fn transcribe(&mut self, samples: &[f32]) -> Result<String, TranscribeError> {
        let result = self
            .model
            .transcribe_samples(samples.to_vec(), 16000, 1, None)
            .map_err(|e| TranscribeError::Inference(e.to_string()))?;

        Ok(result.text)
    }
}

/// A transcription session that accumulates audio for batch inference.
pub struct TranscribeSession {
    /// Accumulated audio buffer (16kHz mono f32).
    audio_buffer: Vec<f32>,
}

impl TranscribeSession {
    /// Feed audio samples (16kHz mono f32).
    /// In batch mode, this just accumulates audio — no inference runs yet.
    /// Returns an empty vec (no partial results).
    pub fn feed_samples(&mut self, samples: &[f32]) -> Vec<TranscriptSegment> {
        self.audio_buffer.extend_from_slice(samples);
        Vec::new()
    }

    /// Run batch inference on the accumulated audio buffer.
    /// Call this when speech ends or recording stops.
    pub fn flush(
        &mut self,
        engine: &Arc<Mutex<ParakeetEngine>>,
    ) -> Result<Vec<TranscriptSegment>, TranscribeError> {
        if self.audio_buffer.is_empty() {
            eprintln!("[sotto] flush: buffer empty, skipping");
            return Ok(Vec::new());
        }

        eprintln!(
            "[sotto] flush: {:.1}s of audio ({} samples)",
            self.audio_buffer.len() as f32 / 16000.0,
            self.audio_buffer.len()
        );

        // Truncate to ~4 minutes (TDT limit is ~5 min, leave margin)
        const MAX_SAMPLES: usize = 4 * 60 * 16000; // 4 min at 16kHz
        if self.audio_buffer.len() > MAX_SAMPLES {
            info!(
                "Truncating audio from {:.1}s to 240s (TDT limit)",
                self.audio_buffer.len() as f32 / 16000.0
            );
            self.audio_buffer.truncate(MAX_SAMPLES);
        }

        eprintln!("[sotto] flush: acquiring engine lock...");
        let mut engine = engine
            .lock()
            .map_err(|e| TranscribeError::Inference(format!("Lock poisoned: {e}")))?;
        eprintln!("[sotto] flush: lock acquired, running inference...");

        let start = std::time::Instant::now();
        let text = engine.transcribe(&self.audio_buffer)?;
        eprintln!("[sotto] flush: inference done in {:.1}s", start.elapsed().as_secs_f32());
        self.audio_buffer.clear();

        let text = text.trim().to_string();
        if text.is_empty() || is_hallucination(&text) {
            return Ok(Vec::new());
        }

        Ok(vec![TranscriptSegment {
            text,
            is_final: true,
        }])
    }

    /// Get accumulated audio buffer length in seconds.
    pub fn buffer_duration_secs(&self) -> f32 {
        self.audio_buffer.len() as f32 / 16000.0
    }
}

/// Returns true if the text looks like a hallucination token
/// (e.g. `[BLANK_AUDIO]`, `(music)`, `[MUSIC]`, `(silence)`).
fn is_hallucination(text: &str) -> bool {
    let t = text.trim();
    (t.starts_with('[') && t.ends_with(']')) || (t.starts_with('(') && t.ends_with(')'))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_transcribe_config_defaults() {
        let config = TranscribeConfig::default();
        assert_eq!(config.language, "en");
    }

    #[test]
    fn test_is_hallucination() {
        assert!(is_hallucination("[BLANK_AUDIO]"));
        assert!(is_hallucination("[MUSIC]"));
        assert!(is_hallucination("[INAUDIBLE]"));
        assert!(is_hallucination("[no speech]"));
        assert!(is_hallucination("(music)"));
        assert!(is_hallucination("(laughter)"));
        assert!(is_hallucination("(silence)"));
        assert!(is_hallucination("  [BLANK_AUDIO]  ")); // with whitespace
        assert!(!is_hallucination("Hello world"));
        assert!(!is_hallucination("This is [a] test"));
        assert!(!is_hallucination(""));
    }

    #[test]
    fn test_session_feed_returns_empty() {
        let mut session = TranscribeSession {
            audio_buffer: Vec::new(),
        };
        let segments = session.feed_samples(&[0.0; 1600]);
        assert!(segments.is_empty());
        assert_eq!(session.buffer_duration_secs(), 0.1);
    }

    #[test]
    fn test_session_buffer_duration() {
        let mut session = TranscribeSession {
            audio_buffer: Vec::new(),
        };
        assert_eq!(session.buffer_duration_secs(), 0.0);
        session.feed_samples(&[0.0; 16000]);
        assert!((session.buffer_duration_secs() - 1.0).abs() < 0.01);
    }
}
