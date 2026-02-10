// Tests for dikto_core top-level types — SessionHandle, ListenConfig, DiktoError,
// RecordingState, ModelInfoRecord, LanguageInfo, and language helper functions.

use dikto_core::audio::AudioError;
use dikto_core::config::DiktoConfig;
use dikto_core::models::ModelError;
use dikto_core::transcribe::TranscribeError;
use dikto_core::vad::VadError;
use dikto_core::{
    parakeet_v3_languages, whisper_languages, DiktoError, LanguageInfo, ListenConfig,
    ModelInfoRecord, RecordingState, SessionHandle,
};

// ---------------------------------------------------------------------------
// SessionHandle
// ---------------------------------------------------------------------------

/// A new SessionHandle should be active (stop_flag = false).
#[test]
fn session_handle_is_active_initially() {
    let handle = SessionHandle::new_for_test();
    assert!(handle.is_active());
}

/// Calling stop() should make is_active() return false.
#[test]
fn session_handle_stop_makes_inactive() {
    let handle = SessionHandle::new_for_test();
    handle.stop();
    assert!(!handle.is_active());
}

/// Calling stop() twice should be harmless (idempotent).
#[test]
fn session_handle_double_stop() {
    let handle = SessionHandle::new_for_test();
    handle.stop();
    handle.stop();
    assert!(!handle.is_active());
}

// ---------------------------------------------------------------------------
// ListenConfig
// ---------------------------------------------------------------------------

/// Default ListenConfig should match the documented defaults.
#[test]
fn listen_config_default() {
    let config = ListenConfig::default();
    assert_eq!(config.language, "en");
    assert_eq!(config.max_duration, 30);
    assert_eq!(config.silence_duration_ms, 1500);
    assert!((config.speech_threshold - 0.35).abs() < f32::EPSILON);
}

/// ListenConfig::from(&DiktoConfig) should copy the relevant fields.
#[test]
fn listen_config_from_dikto_config() {
    let dikto_config = DiktoConfig {
        language: "fr".to_string(),
        max_duration: 60,
        silence_duration_ms: 2000,
        speech_threshold: 0.5,
        ..DiktoConfig::default()
    };
    let listen_config = ListenConfig::from(&dikto_config);
    assert_eq!(listen_config.language, "fr");
    assert_eq!(listen_config.max_duration, 60);
    assert_eq!(listen_config.silence_duration_ms, 2000);
    assert!((listen_config.speech_threshold - 0.5).abs() < f32::EPSILON);
}

// ---------------------------------------------------------------------------
// DiktoError — display messages
// ---------------------------------------------------------------------------

/// DiktoError::Audio should include "Audio error" and the inner message.
#[test]
fn dikto_error_audio_display() {
    let err = DiktoError::Audio("no mic".to_string());
    let msg = err.to_string();
    assert!(msg.contains("Audio error"));
    assert!(msg.contains("no mic"));
}

/// DiktoError::Vad should include "VAD error" and the inner message.
#[test]
fn dikto_error_vad_display() {
    let err = DiktoError::Vad("init fail".to_string());
    let msg = err.to_string();
    assert!(msg.contains("VAD error"));
    assert!(msg.contains("init fail"));
}

/// DiktoError::Transcribe should include "Transcription error".
#[test]
fn dikto_error_transcribe_display() {
    let err = DiktoError::Transcribe("oom".to_string());
    let msg = err.to_string();
    assert!(msg.contains("Transcription error"));
    assert!(msg.contains("oom"));
}

/// DiktoError::Model should include "Model error".
#[test]
fn dikto_error_model_display() {
    let err = DiktoError::Model("missing".to_string());
    let msg = err.to_string();
    assert!(msg.contains("Model error"));
    assert!(msg.contains("missing"));
}

/// DiktoError::NoModel should suggest running setup.
#[test]
fn dikto_error_no_model_display() {
    let err = DiktoError::NoModel;
    assert!(err.to_string().contains("No model loaded"));
}

/// DiktoError::AlreadyRecording should say "Already recording".
#[test]
fn dikto_error_already_recording_display() {
    let err = DiktoError::AlreadyRecording;
    assert!(err.to_string().contains("Already recording"));
}

/// DiktoError::Config should include "Config error".
#[test]
fn dikto_error_config_display() {
    let err = DiktoError::Config("bad json".to_string());
    let msg = err.to_string();
    assert!(msg.contains("Config error"));
    assert!(msg.contains("bad json"));
}

// ---------------------------------------------------------------------------
// DiktoError — From impls
// ---------------------------------------------------------------------------

/// AudioError should convert into DiktoError::Audio.
#[test]
fn dikto_error_from_audio_error() {
    let audio_err = AudioError::NoInputDevice;
    let dikto_err: DiktoError = audio_err.into();
    assert!(dikto_err.to_string().contains("Audio error"));
    assert!(dikto_err.to_string().contains("No input device"));
}

/// VadError should convert into DiktoError::Vad.
#[test]
fn dikto_error_from_vad_error() {
    let vad_err = VadError::Init("silero failed".to_string());
    let dikto_err: DiktoError = vad_err.into();
    assert!(dikto_err.to_string().contains("VAD error"));
}

/// TranscribeError should convert into DiktoError::Transcribe.
#[test]
fn dikto_error_from_transcribe_error() {
    let t_err = TranscribeError::NotLoaded;
    let dikto_err: DiktoError = t_err.into();
    assert!(dikto_err.to_string().contains("Transcription error"));
}

/// ModelError should convert into DiktoError::Model.
#[test]
fn dikto_error_from_model_error() {
    let m_err = ModelError::DownloadFailed("timeout".to_string());
    let dikto_err: DiktoError = m_err.into();
    assert!(dikto_err.to_string().contains("Model error"));
}

// ---------------------------------------------------------------------------
// RecordingState
// ---------------------------------------------------------------------------

/// RecordingState::Listening should be equal to itself and Debug-printable.
#[test]
fn recording_state_listening() {
    let state = RecordingState::Listening;
    assert_eq!(state, RecordingState::Listening);
    assert_ne!(state, RecordingState::Processing);
}

/// RecordingState::Processing should be equal to itself.
#[test]
fn recording_state_processing() {
    let state = RecordingState::Processing;
    assert_eq!(state, RecordingState::Processing);
}

/// RecordingState::Done should carry the transcription text.
#[test]
fn recording_state_done_carries_text() {
    let state = RecordingState::Done {
        text: "hello".to_string(),
    };
    if let RecordingState::Done { text } = &state {
        assert_eq!(text, "hello");
    } else {
        panic!("Expected Done variant");
    }
}

/// RecordingState::Error should carry the error message.
#[test]
fn recording_state_error_carries_message() {
    let state = RecordingState::Error {
        message: "boom".to_string(),
    };
    if let RecordingState::Error { message } = &state {
        assert_eq!(message, "boom");
    } else {
        panic!("Expected Error variant");
    }
}

/// RecordingState should be clonable.
#[test]
fn recording_state_clone() {
    let state = RecordingState::Done {
        text: "hi".to_string(),
    };
    let cloned = state.clone();
    assert_eq!(state, cloned);
}

// ---------------------------------------------------------------------------
// ModelInfoRecord
// ---------------------------------------------------------------------------

/// ModelInfoRecord should store all fields correctly.
#[test]
fn model_info_record_construction() {
    let record = ModelInfoRecord {
        name: "test-model".to_string(),
        size_mb: 100,
        description: "A test model".to_string(),
        is_downloaded: false,
        backend: "Parakeet".to_string(),
    };
    assert_eq!(record.name, "test-model");
    assert_eq!(record.size_mb, 100);
    assert_eq!(record.description, "A test model");
    assert!(!record.is_downloaded);
    assert_eq!(record.backend, "Parakeet");
}

/// ModelInfoRecord should be clonable.
#[test]
fn model_info_record_clone() {
    let record = ModelInfoRecord {
        name: "m".to_string(),
        size_mb: 50,
        description: "d".to_string(),
        is_downloaded: true,
        backend: "Whisper".to_string(),
    };
    let cloned = record.clone();
    assert_eq!(cloned.name, "m");
    assert!(cloned.is_downloaded);
}

// ---------------------------------------------------------------------------
// LanguageInfo
// ---------------------------------------------------------------------------

/// LanguageInfo should store code and name.
#[test]
fn language_info_construction() {
    let info = LanguageInfo {
        code: "en".to_string(),
        name: "English".to_string(),
    };
    assert_eq!(info.code, "en");
    assert_eq!(info.name, "English");
}

/// LanguageInfo should be clonable.
#[test]
fn language_info_clone() {
    let info = LanguageInfo {
        code: "fr".to_string(),
        name: "French".to_string(),
    };
    let cloned = info.clone();
    assert_eq!(cloned.code, "fr");
    assert_eq!(cloned.name, "French");
}

// ---------------------------------------------------------------------------
// parakeet_v3_languages
// ---------------------------------------------------------------------------

/// Parakeet v3 should support exactly 25 European languages.
#[test]
fn parakeet_v3_languages_count() {
    let langs = parakeet_v3_languages();
    assert_eq!(langs.len(), 25);
}

/// English should be in the Parakeet v3 language list.
#[test]
fn parakeet_v3_languages_includes_english() {
    let langs = parakeet_v3_languages();
    assert!(langs.iter().any(|l| l.code == "en" && l.name == "English"));
}

/// The first Parakeet v3 language should be English.
#[test]
fn parakeet_v3_languages_english_is_first() {
    let langs = parakeet_v3_languages();
    assert_eq!(langs[0].code, "en");
    assert_eq!(langs[0].name, "English");
}

// ---------------------------------------------------------------------------
// whisper_languages
// ---------------------------------------------------------------------------

/// Whisper should support 32 languages (top languages + auto).
#[test]
fn whisper_languages_count() {
    let langs = whisper_languages();
    assert_eq!(langs.len(), 32);
}

/// Whisper languages should include "auto" for auto-detection.
#[test]
fn whisper_languages_includes_auto() {
    let langs = whisper_languages();
    assert!(langs
        .iter()
        .any(|l| l.code == "auto" && l.name == "Auto-detect"));
}

/// English should be in the Whisper language list.
#[test]
fn whisper_languages_includes_english() {
    let langs = whisper_languages();
    assert!(langs.iter().any(|l| l.code == "en" && l.name == "English"));
}

/// The first Whisper language should be "auto" (Auto-detect).
#[test]
fn whisper_languages_auto_is_first() {
    let langs = whisper_languages();
    assert_eq!(langs[0].code, "auto");
    assert_eq!(langs[0].name, "Auto-detect");
}
