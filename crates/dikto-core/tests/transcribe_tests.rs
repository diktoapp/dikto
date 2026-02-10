// Tests for dikto_core::transcribe — TranscribeConfig defaults, TranscriptSegment
// construction, and TranscribeError display messages.

use dikto_core::transcribe::{TranscribeConfig, TranscribeError, TranscriptSegment};

// ---------------------------------------------------------------------------
// TranscribeConfig
// ---------------------------------------------------------------------------

/// Default TranscribeConfig should have language "en".
#[test]
fn transcribe_config_default_language() {
    let config = TranscribeConfig::default();
    assert_eq!(config.language, "en");
}

/// TranscribeConfig should accept a custom language.
#[test]
fn transcribe_config_custom_language() {
    let config = TranscribeConfig {
        language: "fr".to_string(),
    };
    assert_eq!(config.language, "fr");
}

// ---------------------------------------------------------------------------
// TranscriptSegment
// ---------------------------------------------------------------------------

/// A TranscriptSegment should store text and is_final fields.
#[test]
fn transcript_segment_construction() {
    let seg = TranscriptSegment {
        text: "hello world".to_string(),
        is_final: true,
    };
    assert_eq!(seg.text, "hello world");
    assert!(seg.is_final);
}

/// TranscriptSegment should be clonable.
#[test]
fn transcript_segment_clone() {
    let seg = TranscriptSegment {
        text: "test".to_string(),
        is_final: false,
    };
    let cloned = seg.clone();
    assert_eq!(cloned.text, "test");
    assert!(!cloned.is_final);
}

/// TranscriptSegment should implement Debug.
#[test]
fn transcript_segment_debug() {
    let seg = TranscriptSegment {
        text: "debug".to_string(),
        is_final: true,
    };
    let debug_str = format!("{seg:?}");
    assert!(debug_str.contains("debug"));
    assert!(debug_str.contains("true"));
}

// ---------------------------------------------------------------------------
// TranscribeError display
// ---------------------------------------------------------------------------

/// TranscribeError::ModelLoad should include the failure reason.
#[test]
fn transcribe_error_model_load_display() {
    let err = TranscribeError::ModelLoad("bad path".to_string());
    assert!(err.to_string().contains("bad path"));
    assert!(err.to_string().contains("load model"));
}

/// TranscribeError::Inference should include the failure reason.
#[test]
fn transcribe_error_inference_display() {
    let err = TranscribeError::Inference("oom".to_string());
    assert!(err.to_string().contains("oom"));
    assert!(err.to_string().contains("Inference"));
}

/// TranscribeError::NotLoaded should produce a human-readable message.
#[test]
fn transcribe_error_not_loaded_display() {
    let err = TranscribeError::NotLoaded;
    assert!(err.to_string().contains("not loaded"));
}
