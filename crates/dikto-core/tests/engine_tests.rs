// Tests for dikto_core::engine — hallucination detection, AsrSession buffer
// accumulation, feed_samples, and buffer_duration_secs.

use dikto_core::engine::{is_hallucination, AsrSession};

// ---------------------------------------------------------------------------
// is_hallucination — bracket-style tokens
// ---------------------------------------------------------------------------

/// "[BLANK_AUDIO]" (case-insensitive) is a known hallucination token.
#[test]
fn hallucination_blank_audio_bracket() {
    assert!(is_hallucination("[BLANK_AUDIO]"));
}

/// "[MUSIC]" is a known hallucination token.
#[test]
fn hallucination_music_bracket() {
    assert!(is_hallucination("[MUSIC]"));
}

/// "[INAUDIBLE]" is a known hallucination token.
#[test]
fn hallucination_inaudible_bracket() {
    assert!(is_hallucination("[INAUDIBLE]"));
}

/// "[SILENCE]" is a known hallucination token.
#[test]
fn hallucination_silence_bracket() {
    assert!(is_hallucination("[SILENCE]"));
}

/// "[no speech]" is a known hallucination token.
#[test]
fn hallucination_no_speech_bracket() {
    assert!(is_hallucination("[no speech]"));
}

/// "[APPLAUSE]" is a known hallucination token.
#[test]
fn hallucination_applause_bracket() {
    assert!(is_hallucination("[APPLAUSE]"));
}

/// "[LAUGHTER]" is a known hallucination token.
#[test]
fn hallucination_laughter_bracket() {
    assert!(is_hallucination("[LAUGHTER]"));
}

// ---------------------------------------------------------------------------
// is_hallucination — paren-style tokens
// ---------------------------------------------------------------------------

/// "(music)" is a known hallucination token.
#[test]
fn hallucination_music_paren() {
    assert!(is_hallucination("(music)"));
}

/// "(silence)" is a known hallucination token.
#[test]
fn hallucination_silence_paren() {
    assert!(is_hallucination("(silence)"));
}

/// "(laughter)" is a known hallucination token.
#[test]
fn hallucination_laughter_paren() {
    assert!(is_hallucination("(laughter)"));
}

/// "(applause)" is a known hallucination token.
#[test]
fn hallucination_applause_paren() {
    assert!(is_hallucination("(applause)"));
}

/// "(no speech)" is a known hallucination token.
#[test]
fn hallucination_no_speech_paren() {
    assert!(is_hallucination("(no speech)"));
}

/// "(blank audio)" is a known hallucination token.
#[test]
fn hallucination_blank_audio_paren() {
    assert!(is_hallucination("(blank audio)"));
}

// ---------------------------------------------------------------------------
// is_hallucination — whitespace handling
// ---------------------------------------------------------------------------

/// Leading/trailing whitespace should be trimmed before checking.
#[test]
fn hallucination_with_whitespace() {
    assert!(is_hallucination("  [BLANK_AUDIO]  "));
}

// ---------------------------------------------------------------------------
// is_hallucination — non-hallucination text
// ---------------------------------------------------------------------------

/// Normal speech text should not be detected as a hallucination.
#[test]
fn not_hallucination_normal_text() {
    assert!(!is_hallucination("Hello world"));
}

/// Text containing brackets but not matching a token should not be hallucination.
#[test]
fn not_hallucination_brackets_in_text() {
    assert!(!is_hallucination("This is [a] test"));
}

/// Empty string should not be a hallucination.
#[test]
fn not_hallucination_empty_string() {
    assert!(!is_hallucination(""));
}

/// Text starting with a paren-style prefix but continuing with speech is not hallucination.
#[test]
fn not_hallucination_paren_prefix_with_speech() {
    assert!(!is_hallucination("(pause) let me think"));
}

/// Text starting with a bracket-style prefix but continuing with speech is not hallucination.
#[test]
fn not_hallucination_bracket_prefix_with_speech() {
    assert!(!is_hallucination("[unclear] something here"));
}

// ---------------------------------------------------------------------------
// AsrSession — feed_samples
// ---------------------------------------------------------------------------

/// feed_samples should return an empty vec (batch inference happens in flush).
#[test]
fn feed_samples_returns_empty() {
    let mut session = AsrSession::new("en".to_string());
    let samples = vec![0.1f32; 1600];
    let result = session.feed_samples(&samples);
    assert!(result.is_empty());
}

/// feed_samples should accumulate audio in the buffer.
#[test]
fn feed_samples_accumulates_buffer() {
    let mut session = AsrSession::new("en".to_string());
    // Feed 0.5s of audio
    session.feed_samples(&vec![0.0f32; 8000]);
    assert!((session.buffer_duration_secs() - 0.5).abs() < 0.01);
    // Feed another 0.5s
    session.feed_samples(&vec![0.0f32; 8000]);
    assert!((session.buffer_duration_secs() - 1.0).abs() < 0.01);
}

// ---------------------------------------------------------------------------
// AsrSession — buffer_duration_secs
// ---------------------------------------------------------------------------

/// An empty session should have 0 buffer duration.
#[test]
fn buffer_duration_empty_is_zero() {
    let session = AsrSession::new("en".to_string());
    assert!((session.buffer_duration_secs() - 0.0).abs() < f32::EPSILON);
}

/// After feeding 16000 samples (1 second at 16kHz), duration should be ~1.0s.
#[test]
fn buffer_duration_one_second() {
    let mut session = AsrSession::new("en".to_string());
    session.feed_samples(&vec![0.0f32; 16000]);
    assert!((session.buffer_duration_secs() - 1.0).abs() < 0.01);
}

/// After feeding 8000 samples (0.5 seconds at 16kHz), duration should be ~0.5s.
#[test]
fn buffer_duration_half_second() {
    let mut session = AsrSession::new("en".to_string());
    session.feed_samples(&vec![0.0f32; 8000]);
    assert!((session.buffer_duration_secs() - 0.5).abs() < 0.01);
}
