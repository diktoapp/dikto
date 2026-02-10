// Tests for dikto_core::vad — VAD config defaults, processor creation, state
// machine behavior with silence, chunk size, reset, and event equality.

use dikto_core::vad::{VadConfig, VadEvent, VadProcessor, VadState};

// ---------------------------------------------------------------------------
// VadConfig defaults
// ---------------------------------------------------------------------------

/// VadConfig::default() should return the documented threshold and timings.
#[test]
fn vad_config_defaults() {
    let config = VadConfig::default();
    assert!((config.speech_threshold - 0.35).abs() < f32::EPSILON);
    assert_eq!(config.silence_duration_ms, 1500);
    assert_eq!(config.min_speech_duration_ms, 250);
    assert_eq!(config.sample_rate, 16000);
    assert_eq!(config.speech_activation_frames, 8);
}

/// A custom VadConfig should preserve user-set values.
#[test]
fn vad_config_custom_values() {
    let config = VadConfig {
        speech_threshold: 0.5,
        silence_duration_ms: 2000,
        min_speech_duration_ms: 500,
        sample_rate: 16000,
        speech_activation_frames: 4,
    };
    assert!((config.speech_threshold - 0.5).abs() < f32::EPSILON);
    assert_eq!(config.silence_duration_ms, 2000);
    assert_eq!(config.min_speech_duration_ms, 500);
    assert_eq!(config.speech_activation_frames, 4);
}

// ---------------------------------------------------------------------------
// VadProcessor creation
// ---------------------------------------------------------------------------

/// Creating a VadProcessor with default config should succeed.
#[test]
fn processor_creation_succeeds() {
    let config = VadConfig::default();
    let vad = VadProcessor::new(config);
    assert!(vad.is_ok());
}

/// A new processor should start in the Idle state.
#[test]
fn processor_starts_idle() {
    let vad = VadProcessor::new(VadConfig::default()).unwrap();
    assert_eq!(vad.state(), VadState::Idle);
}

/// chunk_size should return 512 (32ms at 16kHz).
#[test]
fn processor_chunk_size_is_512() {
    let vad = VadProcessor::new(VadConfig::default()).unwrap();
    assert_eq!(vad.chunk_size(), 512);
}

// ---------------------------------------------------------------------------
// State machine — silence
// ---------------------------------------------------------------------------

/// Feeding silence should keep the processor in Idle and return Silence events.
#[test]
fn silence_stays_idle() {
    let mut vad = VadProcessor::new(VadConfig::default()).unwrap();
    let silence = vec![0.0f32; 512];
    let event = vad.process_chunk(&silence).unwrap();
    assert_eq!(event, VadEvent::Silence);
    assert_eq!(vad.state(), VadState::Idle);
}

/// Multiple silence chunks should all return Silence and keep state Idle.
#[test]
fn multiple_silence_chunks_stay_idle() {
    let mut vad = VadProcessor::new(VadConfig::default()).unwrap();
    let silence = vec![0.0f32; 512];
    for _ in 0..20 {
        let event = vad.process_chunk(&silence).unwrap();
        assert_eq!(event, VadEvent::Silence);
    }
    assert_eq!(vad.state(), VadState::Idle);
}

// ---------------------------------------------------------------------------
// State machine — pending (no false trigger)
// ---------------------------------------------------------------------------

/// Silence frames should not accumulate enough speech to trigger SpeechStart.
#[test]
fn pending_no_false_trigger() {
    let config = VadConfig {
        speech_activation_frames: 8,
        ..VadConfig::default()
    };
    let mut vad = VadProcessor::new(config).unwrap();
    let silence = vec![0.0f32; 512];
    for _ in 0..7 {
        let event = vad.process_chunk(&silence).unwrap();
        assert_eq!(event, VadEvent::Silence);
    }
    // After only silence, state should still be Idle (never transitioned to Speaking)
    assert_eq!(vad.state(), VadState::Idle);
}

// ---------------------------------------------------------------------------
// Reset
// ---------------------------------------------------------------------------

/// reset() should return the processor to Idle state.
#[test]
fn reset_returns_to_idle() {
    let mut vad = VadProcessor::new(VadConfig::default()).unwrap();
    // Process some silence first
    let silence = vec![0.0f32; 512];
    vad.process_chunk(&silence).unwrap();
    // Reset
    vad.reset();
    assert_eq!(vad.state(), VadState::Idle);
}

/// After reset, processing silence should behave like a fresh processor.
#[test]
fn reset_then_process_silence() {
    let mut vad = VadProcessor::new(VadConfig::default()).unwrap();
    let silence = vec![0.0f32; 512];
    // Process, reset, then process again
    vad.process_chunk(&silence).unwrap();
    vad.reset();
    let event = vad.process_chunk(&silence).unwrap();
    assert_eq!(event, VadEvent::Silence);
    assert_eq!(vad.state(), VadState::Idle);
}

// ---------------------------------------------------------------------------
// VadEvent equality
// ---------------------------------------------------------------------------

/// VadEvent variants should support equality comparison.
#[test]
fn vad_event_equality() {
    assert_eq!(VadEvent::SpeechStart, VadEvent::SpeechStart);
    assert_eq!(VadEvent::SpeechContinue, VadEvent::SpeechContinue);
    assert_eq!(VadEvent::SpeechEnd, VadEvent::SpeechEnd);
    assert_eq!(VadEvent::Silence, VadEvent::Silence);
    assert_ne!(VadEvent::SpeechStart, VadEvent::Silence);
    assert_ne!(VadEvent::SpeechEnd, VadEvent::SpeechContinue);
}
