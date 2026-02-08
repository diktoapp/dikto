use std::path::Path;
use thiserror::Error;
use tracing::info;

use parakeet_rs::{ParakeetTDT, Transcriber};
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

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

    /// Run batch inference on audio samples.
    /// Returns the transcribed text.
    pub fn transcribe(&mut self, samples: &[f32]) -> Result<String, TranscribeError> {
        let result = self
            .model
            .transcribe_samples(samples.to_vec(), 16000, 1, None)
            .map_err(|e| TranscribeError::Inference(e.to_string()))?;

        Ok(result.text)
    }
}

// ---------------------------------------------------------------------------
// Whisper engine (whisper.cpp via whisper-rs)
// ---------------------------------------------------------------------------

/// Whisper engine that keeps the model loaded in memory.
pub struct WhisperEngine {
    ctx: WhisperContext,
}

// WhisperContext wraps a C pointer — we guard access via Mutex externally.
unsafe impl Send for WhisperEngine {}
unsafe impl Sync for WhisperEngine {}

impl WhisperEngine {
    /// Load a Whisper GGML model from a directory.
    /// The directory must contain a single `.bin` file.
    pub fn load(model_dir: &Path) -> Result<Self, TranscribeError> {
        info!("Loading Whisper model from {}", model_dir.display());

        // Find the .bin file in the model directory
        let bin_path = std::fs::read_dir(model_dir)
            .map_err(|e| TranscribeError::ModelLoad(e.to_string()))?
            .filter_map(|entry| entry.ok())
            .find(|entry| {
                entry
                    .path()
                    .extension()
                    .map(|ext| ext == "bin")
                    .unwrap_or(false)
            })
            .map(|entry| entry.path())
            .ok_or_else(|| {
                TranscribeError::ModelLoad("No .bin file found in model directory".to_string())
            })?;

        let ctx = WhisperContext::new_with_params(
            bin_path.to_str().unwrap_or_default(),
            WhisperContextParameters::default(),
        )
        .map_err(|e| TranscribeError::ModelLoad(format!("whisper init failed: {e}")))?;

        info!("Whisper model loaded successfully");
        Ok(Self { ctx })
    }

    /// Run batch inference on audio samples.
    /// `language` should be an ISO-639-1 code (e.g. "en", "es") or "auto".
    pub fn transcribe(&self, samples: &[f32], language: &str) -> Result<String, TranscribeError> {
        let mut state = self
            .ctx
            .create_state()
            .map_err(|e| TranscribeError::Inference(format!("create state: {e}")))?;

        let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });

        if language == "auto" {
            params.set_language(None);
        } else {
            params.set_language(Some(language));
        }

        // Disable token timestamps for speed
        params.set_token_timestamps(false);
        // Single-segment mode
        params.set_single_segment(false);
        params.set_print_special(false);
        params.set_print_progress(false);
        params.set_print_realtime(false);
        params.set_print_timestamps(false);

        state
            .full(params, samples)
            .map_err(|e| TranscribeError::Inference(format!("whisper inference: {e}")))?;

        let n_segments = state.full_n_segments().map_err(|e| {
            TranscribeError::Inference(format!("get segments: {e}"))
        })?;

        let mut text = String::new();
        for i in 0..n_segments {
            if let Ok(seg) = state.full_get_segment_text(i) {
                text.push_str(&seg);
            }
        }

        Ok(text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_transcribe_config_defaults() {
        let config = TranscribeConfig::default();
        assert_eq!(config.language, "en");
    }
}
