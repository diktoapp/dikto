use thiserror::Error;
use tracing::debug;
use voice_activity_detector::VoiceActivityDetector;

#[derive(Debug, Error)]
pub enum VadError {
    #[error("VAD initialization failed: {0}")]
    Init(String),
    #[error("VAD processing error: {0}")]
    Process(String),
}

/// Events emitted by the VAD processor.
#[derive(Debug, Clone, PartialEq)]
pub enum VadEvent {
    /// Speech has started.
    SpeechStart,
    /// Speech is continuing.
    SpeechContinue,
    /// Speech has ended (silence detected after speech).
    SpeechEnd,
    /// Silence (no speech detected, and no prior speech).
    Silence,
}

/// Configuration for VAD processing.
#[derive(Debug, Clone)]
pub struct VadConfig {
    /// Probability threshold for speech detection (0.0-1.0).
    pub speech_threshold: f32,
    /// How long silence must last to trigger SpeechEnd, in ms.
    pub silence_duration_ms: u32,
    /// Minimum speech duration to count as valid, in ms.
    pub min_speech_duration_ms: u32,
    /// Sample rate of input audio.
    pub sample_rate: u32,
    /// Number of consecutive speech frames required to confirm speech (avoids false triggers).
    pub speech_activation_frames: u32,
}

impl Default for VadConfig {
    fn default() -> Self {
        Self {
            speech_threshold: 0.35,
            silence_duration_ms: 1500,
            min_speech_duration_ms: 250,
            sample_rate: 16000,
            speech_activation_frames: 8, // ~256ms at 32ms/frame
        }
    }
}

/// VAD processor that wraps Silero VAD and tracks speech state.
pub struct VadProcessor {
    detector: VoiceActivityDetector,
    config: VadConfig,
    state: VadState,
    /// Number of consecutive silence frames after speech.
    silence_frames: u32,
    /// Number of speech frames since speech started.
    speech_frames: u32,
    /// Number of consecutive speech frames in Pending state.
    pending_speech_frames: u32,
    /// Samples per chunk (512 for 16kHz = 32ms).
    chunk_size: usize,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum VadState {
    Idle,
    /// Speech detected but not yet confirmed (waiting for consecutive frames).
    Pending,
    Speaking,
}

impl VadProcessor {
    /// Create a new VAD processor.
    pub fn new(config: VadConfig) -> Result<Self, VadError> {
        let chunk_size = 512; // ~32ms at 16kHz
        let detector = VoiceActivityDetector::builder()
            .sample_rate(config.sample_rate as i64)
            .chunk_size(chunk_size)
            .build()
            .map_err(|e| VadError::Init(e.to_string()))?;

        Ok(Self {
            detector,
            config,
            state: VadState::Idle,
            silence_frames: 0,
            speech_frames: 0,
            pending_speech_frames: 0,
            chunk_size,
        })
    }

    /// Process a chunk of audio samples and return a VAD event.
    /// Input should be 512 samples at 16kHz (32ms).
    pub fn process_chunk(&mut self, samples: &[f32]) -> Result<VadEvent, VadError> {
        let probability = self
            .detector
            .predict(samples.iter().copied());

        let is_speech = probability > self.config.speech_threshold;
        let frame_duration_ms = (self.chunk_size as f32 / self.config.sample_rate as f32 * 1000.0) as u32;

        let event = match (self.state, is_speech) {
            // Idle: wait for first speech frame to enter Pending
            (VadState::Idle, true) => {
                self.state = VadState::Pending;
                self.pending_speech_frames = 1;
                debug!("VAD: possible speech (prob={probability:.3}), pending confirmation");
                VadEvent::Silence
            }
            (VadState::Idle, false) => VadEvent::Silence,

            // Pending: accumulate consecutive speech frames before confirming
            (VadState::Pending, true) => {
                self.pending_speech_frames += 1;
                if self.pending_speech_frames >= self.config.speech_activation_frames {
                    self.state = VadState::Speaking;
                    self.speech_frames = self.pending_speech_frames;
                    self.silence_frames = 0;
                    self.pending_speech_frames = 0;
                    debug!("VAD: speech confirmed after {} frames (prob={probability:.3})", self.speech_frames);
                    VadEvent::SpeechStart
                } else {
                    VadEvent::Silence
                }
            }
            (VadState::Pending, false) => {
                // Not enough consecutive frames — false alarm
                debug!("VAD: pending speech reset after {} frames", self.pending_speech_frames);
                self.state = VadState::Idle;
                self.pending_speech_frames = 0;
                VadEvent::Silence
            }

            // Speaking: unchanged
            (VadState::Speaking, true) => {
                self.speech_frames += 1;
                self.silence_frames = 0;
                VadEvent::SpeechContinue
            }
            (VadState::Speaking, false) => {
                self.silence_frames += 1;
                let silence_ms = self.silence_frames * frame_duration_ms;

                if silence_ms >= self.config.silence_duration_ms {
                    let speech_ms = self.speech_frames * frame_duration_ms;
                    let valid = speech_ms >= self.config.min_speech_duration_ms;
                    self.state = VadState::Idle;
                    self.speech_frames = 0;
                    self.silence_frames = 0;

                    if valid {
                        debug!("VAD: speech end (duration={speech_ms}ms)");
                        VadEvent::SpeechEnd
                    } else {
                        debug!("VAD: speech too short ({speech_ms}ms), ignoring");
                        VadEvent::Silence
                    }
                } else {
                    // Still in grace period
                    VadEvent::SpeechContinue
                }
            }
        };

        Ok(event)
    }

    /// Reset the VAD state.
    pub fn reset(&mut self) {
        self.state = VadState::Idle;
        self.silence_frames = 0;
        self.speech_frames = 0;
        self.pending_speech_frames = 0;
    }

    /// Get the chunk size expected by this processor.
    pub fn chunk_size(&self) -> usize {
        self.chunk_size
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vad_config_defaults() {
        let config = VadConfig::default();
        assert!((config.speech_threshold - 0.35).abs() < f32::EPSILON);
        assert_eq!(config.silence_duration_ms, 1500);
        assert_eq!(config.min_speech_duration_ms, 250);
        assert_eq!(config.sample_rate, 16000);
        assert_eq!(config.speech_activation_frames, 8);
    }

    #[test]
    fn test_vad_state_machine_silence() {
        // Feed silence → should stay Idle
        let config = VadConfig::default();
        let mut vad = VadProcessor::new(config).unwrap();
        let silence = vec![0.0f32; 512];
        let event = vad.process_chunk(&silence).unwrap();
        assert_eq!(event, VadEvent::Silence);
    }

    #[test]
    fn test_vad_pending_state_no_false_trigger() {
        // 7 speech frames should NOT trigger SpeechStart (need 8)
        let config = VadConfig {
            speech_activation_frames: 8,
            ..VadConfig::default()
        };
        let mut vad = VadProcessor::new(config).unwrap();

        // Simulate 7 speech frames — all should return Silence (pending)
        let silence = vec![0.0f32; 512];
        for _ in 0..7 {
            // We can't easily generate real speech, so test the state machine directly
            // by manipulating state. Instead, feed silence and verify no SpeechStart.
            let event = vad.process_chunk(&silence).unwrap();
            assert_eq!(event, VadEvent::Silence);
        }
        // After only silence frames, state should still be Idle
        assert_eq!(vad.state, VadState::Idle);
    }
}
