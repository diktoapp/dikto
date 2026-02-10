// Tests for dikto_core::audio — AudioCaptureConfig defaults and AudioError
// display messages. Actual audio capture requires hardware and is not tested.

use dikto_core::audio::{AudioCaptureConfig, AudioError};

// ---------------------------------------------------------------------------
// AudioCaptureConfig defaults
// ---------------------------------------------------------------------------

/// Default sample rate should be 16000 Hz (required by Whisper/Parakeet).
#[test]
fn default_sample_rate_is_16khz() {
    let config = AudioCaptureConfig::default();
    assert_eq!(config.target_sample_rate, 16000);
}

/// Default buffer capacity should be 30 seconds at 16kHz (480000 samples).
#[test]
fn default_buffer_capacity_is_30s() {
    let config = AudioCaptureConfig::default();
    assert_eq!(config.buffer_capacity, 16000 * 30);
}

/// A custom AudioCaptureConfig should preserve user-set values.
#[test]
fn custom_audio_config() {
    let config = AudioCaptureConfig {
        target_sample_rate: 44100,
        buffer_capacity: 44100 * 10,
    };
    assert_eq!(config.target_sample_rate, 44100);
    assert_eq!(config.buffer_capacity, 441000);
}

// ---------------------------------------------------------------------------
// AudioError display
// ---------------------------------------------------------------------------

/// AudioError::NoInputDevice should produce a human-readable message.
#[test]
fn audio_error_no_input_device_display() {
    let err = AudioError::NoInputDevice;
    assert!(err.to_string().contains("No input device"));
}

/// AudioError::NoSupportedConfig should produce a human-readable message.
#[test]
fn audio_error_no_supported_config_display() {
    let err = AudioError::NoSupportedConfig;
    assert!(err.to_string().contains("No supported input config"));
}

/// AudioError::StreamBuild should include the failure reason.
#[test]
fn audio_error_stream_build_display() {
    let err = AudioError::StreamBuild("device busy".to_string());
    let msg = err.to_string();
    assert!(msg.contains("stream"));
    assert!(msg.contains("device busy"));
}

/// AudioError::StreamPlay should include the failure reason.
#[test]
fn audio_error_stream_play_display() {
    let err = AudioError::StreamPlay("permission denied".to_string());
    let msg = err.to_string();
    assert!(msg.contains("stream"));
    assert!(msg.contains("permission denied"));
}

/// AudioError::Device should include the device error message.
#[test]
fn audio_error_device_display() {
    let err = AudioError::Device("unplugged".to_string());
    let msg = err.to_string();
    assert!(msg.contains("unplugged"));
}
