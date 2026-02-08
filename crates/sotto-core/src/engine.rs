use std::path::Path;
use std::sync::{Arc, Mutex};

use tracing::{debug, info, warn};

use crate::models::ModelBackend;
use crate::transcribe::{
    ParakeetEngine, TranscribeConfig, TranscribeError, TranscriptSegment, WhisperEngine,
};

/// Unified ASR engine wrapping both Parakeet and Whisper backends.
pub enum AsrEngine {
    Parakeet(Box<ParakeetEngine>),
    Whisper(WhisperEngine),
}

unsafe impl Send for AsrEngine {}
unsafe impl Sync for AsrEngine {}

impl AsrEngine {
    /// Load a model based on backend type.
    pub fn load(backend: ModelBackend, model_dir: &Path) -> Result<Self, TranscribeError> {
        match backend {
            ModelBackend::Parakeet => Ok(AsrEngine::Parakeet(Box::new(ParakeetEngine::load(model_dir)?))),
            ModelBackend::Whisper => Ok(AsrEngine::Whisper(WhisperEngine::load(model_dir)?)),
        }
    }

    /// Create a new transcription session.
    pub fn create_session(&self, config: TranscribeConfig) -> AsrSession {
        AsrSession {
            audio_buffer: Vec::new(),
            language: config.language,
        }
    }
}

/// A loaded engine paired with the model name it was loaded from.
pub struct LoadedEngine {
    pub model_name: String,
    pub engine: AsrEngine,
}

/// Unified transcription session that accumulates audio for batch inference.
pub struct AsrSession {
    audio_buffer: Vec<f32>,
    language: String,
}

impl AsrSession {
    /// Feed audio samples (16kHz mono f32).
    pub fn feed_samples(&mut self, samples: &[f32]) -> Vec<TranscriptSegment> {
        self.audio_buffer.extend_from_slice(samples);
        Vec::new()
    }

    /// Run batch inference on the accumulated audio buffer.
    pub fn flush(
        &mut self,
        engine: &Arc<Mutex<Option<LoadedEngine>>>,
    ) -> Result<Vec<TranscriptSegment>, TranscribeError> {
        if self.audio_buffer.is_empty() {
            warn!("flush: buffer empty, skipping");
            return Ok(Vec::new());
        }

        debug!(
            "flush: {:.1}s of audio ({} samples)",
            self.audio_buffer.len() as f32 / 16000.0,
            self.audio_buffer.len()
        );

        // Cap at ~4 minutes
        const MAX_SAMPLES: usize = 4 * 60 * 16000;
        if self.audio_buffer.len() > MAX_SAMPLES {
            info!(
                "Truncating audio from {:.1}s to 240s",
                self.audio_buffer.len() as f32 / 16000.0
            );
            self.audio_buffer.truncate(MAX_SAMPLES);
        }

        debug!("flush: acquiring engine lock...");
        let mut guard = engine
            .lock()
            .map_err(|e| TranscribeError::Inference(format!("Lock poisoned: {e}")))?;

        let loaded = guard
            .as_mut()
            .ok_or(TranscribeError::NotLoaded)?;

        debug!("flush: lock acquired, running inference...");

        let start = std::time::Instant::now();
        let text = match &mut loaded.engine {
            AsrEngine::Parakeet(e) => e.transcribe(&self.audio_buffer)?,
            AsrEngine::Whisper(e) => e.transcribe(&self.audio_buffer, &self.language)?,
        };
        debug!(
            "flush: inference done in {:.1}s",
            start.elapsed().as_secs_f32()
        );
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

/// Returns true if the text looks like a known ASR hallucination token.
fn is_hallucination(text: &str) -> bool {
    let t = text.trim().to_lowercase();
    let hallucinations = [
        "[blank_audio]",
        "[music]",
        "[inaudible]",
        "[silence]",
        "[no speech]",
        "[applause]",
        "[laughter]",
        "(music)",
        "(silence)",
        "(laughter)",
        "(applause)",
        "(no speech)",
        "(blank audio)",
    ];
    hallucinations.contains(&t.as_str())
}

#[cfg(test)]
mod tests {
    use super::*;

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
        // These should NOT be hallucinations (valid speech with brackets/parens)
        assert!(!is_hallucination("(pause) let me think"));
        assert!(!is_hallucination("[unclear] something here"));
    }
}
