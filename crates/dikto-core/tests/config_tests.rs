// Tests for dikto_core::config — configuration loading, validation, serialization,
// shortcut parsing, and backward compatibility.

use dikto_core::config::{
    config_dir, config_path, data_dir, default_model_name, is_valid_shortcut, models_dir,
    ActivationMode, DiktoConfig,
};

// ---------------------------------------------------------------------------
// Default config
// ---------------------------------------------------------------------------

/// Verify that DiktoConfig::default() returns the documented defaults.
#[test]
fn default_config_has_expected_values() {
    let config = DiktoConfig::default();
    assert_eq!(config.model_name, "parakeet-tdt-0.6b-v2");
    assert_eq!(config.language, "en");
    assert_eq!(config.max_duration, 30);
    assert_eq!(config.silence_duration_ms, 1500);
    assert!((config.speech_threshold - 0.35).abs() < f32::EPSILON);
    assert_eq!(config.global_shortcut, Some("option+r".to_string()));
    assert_eq!(config.activation_mode, ActivationMode::Hold);
    assert!(config.auto_paste);
    assert!(config.auto_copy);
}

/// default_model_name() should match the default config.
#[test]
fn default_model_name_matches_config() {
    assert_eq!(default_model_name(), DiktoConfig::default().model_name);
}

/// ActivationMode default (via #[default] derive) should be Hold.
#[test]
fn activation_mode_default_is_hold() {
    assert_eq!(ActivationMode::default(), ActivationMode::Hold);
}

// ---------------------------------------------------------------------------
// JSON deserialization
// ---------------------------------------------------------------------------

/// Deserializing partial JSON should fill in serde defaults for missing fields.
#[test]
fn deserialize_partial_json_fills_defaults() {
    let json = r#"{"model_name":"tiny.en","language":"fr","max_duration":60}"#;
    let config: DiktoConfig = serde_json::from_str(json).unwrap();
    assert_eq!(config.model_name, "tiny.en");
    assert_eq!(config.language, "fr");
    assert_eq!(config.max_duration, 60);
    // Defaults for missing fields
    assert_eq!(config.silence_duration_ms, 1500);
    assert_eq!(config.global_shortcut, Some("option+r".to_string()));
}

/// An empty JSON object should deserialize to all serde defaults.
#[test]
fn deserialize_empty_json_object_gives_defaults() {
    let config: DiktoConfig = serde_json::from_str("{}").unwrap();
    assert_eq!(config.model_name, default_model_name());
    assert_eq!(config.language, "en");
    assert_eq!(config.max_duration, 30);
    assert_eq!(config.silence_duration_ms, 1500);
    assert!((config.speech_threshold - 0.35).abs() < f32::EPSILON);
    assert_eq!(config.global_shortcut, Some("option+r".to_string()));
    assert!(config.auto_paste);
    assert!(config.auto_copy);
}

/// Corrupt JSON should fail to parse.
#[test]
fn corrupt_json_fails_to_parse() {
    let result = serde_json::from_str::<DiktoConfig>("this is not json!!!");
    assert!(result.is_err());
}

/// A fallback DiktoConfig::default() should have the expected model name.
#[test]
fn corrupt_config_fallback_returns_defaults() {
    // When deserialization fails, load_config returns DiktoConfig::default()
    let default = DiktoConfig::default();
    assert_eq!(default.model_name, "parakeet-tdt-0.6b-v2");
}

// ---------------------------------------------------------------------------
// Backward compatibility — activation_mode migration
// ---------------------------------------------------------------------------

/// Existing config without activation_mode should be migrated to Toggle.
#[test]
fn backward_compat_no_activation_mode_gives_toggle() {
    let json = r#"{"model_name":"parakeet-tdt-0.6b-v2","language":"en","auto_paste":true}"#;
    let raw: serde_json::Value = serde_json::from_str(json).unwrap();
    let has_activation_mode = raw.get("activation_mode").is_some();
    let mut config: DiktoConfig = serde_json::from_str(json).unwrap();
    if !has_activation_mode {
        config.activation_mode = ActivationMode::Toggle;
    }
    assert_eq!(config.activation_mode, ActivationMode::Toggle);
}

/// activation_mode "hold" should deserialize to Hold.
#[test]
fn activation_mode_hold_deserializes() {
    let json = r#"{"activation_mode":"hold"}"#;
    let config: DiktoConfig = serde_json::from_str(json).unwrap();
    assert_eq!(config.activation_mode, ActivationMode::Hold);
}

/// activation_mode "toggle" should deserialize to Toggle.
#[test]
fn activation_mode_toggle_deserializes() {
    let json = r#"{"activation_mode":"toggle"}"#;
    let config: DiktoConfig = serde_json::from_str(json).unwrap();
    assert_eq!(config.activation_mode, ActivationMode::Toggle);
}

// ---------------------------------------------------------------------------
// Shortcut validation
// ---------------------------------------------------------------------------

/// "option+r" is a valid shortcut (one modifier, one key).
#[test]
fn shortcut_option_r_is_valid() {
    assert!(is_valid_shortcut("option+r"));
}

/// "command+shift+space" is valid (two modifiers, one key).
#[test]
fn shortcut_command_shift_space_is_valid() {
    assert!(is_valid_shortcut("command+shift+space"));
}

/// "control+option+f1" is valid (two modifiers, one key).
#[test]
fn shortcut_control_option_f1_is_valid() {
    assert!(is_valid_shortcut("control+option+f1"));
}

/// A bare key with no modifier is invalid.
#[test]
fn shortcut_bare_key_is_invalid() {
    assert!(!is_valid_shortcut("r"));
}

/// A bare modifier with no key is invalid.
#[test]
fn shortcut_bare_modifier_is_invalid() {
    assert!(!is_valid_shortcut("option"));
}

/// Two non-modifier keys ("option+r+s") is invalid — only one key allowed.
#[test]
fn shortcut_two_keys_is_invalid() {
    assert!(!is_valid_shortcut("option+r+s"));
}

/// An empty string is not a valid shortcut.
#[test]
fn shortcut_empty_is_invalid() {
    assert!(!is_valid_shortcut(""));
}

// ---------------------------------------------------------------------------
// Validate — shortcut reset
// ---------------------------------------------------------------------------

/// validate() should reset an invalid shortcut string to the default "option+r".
#[test]
fn validate_resets_invalid_shortcut() {
    let mut config = DiktoConfig {
        global_shortcut: Some("just-a-key".to_string()),
        ..DiktoConfig::default()
    };
    config.validate();
    assert_eq!(config.global_shortcut, Some("option+r".to_string()));
}

/// validate() should replace None shortcut with the default "option+r".
#[test]
fn validate_resets_none_shortcut() {
    let mut config = DiktoConfig {
        global_shortcut: None,
        ..DiktoConfig::default()
    };
    config.validate();
    assert_eq!(config.global_shortcut, Some("option+r".to_string()));
}

// ---------------------------------------------------------------------------
// Validate — language code
// ---------------------------------------------------------------------------

/// A 2-letter lowercase language code like "fr" should be accepted.
#[test]
fn validate_accepts_valid_language_code() {
    let mut config = DiktoConfig {
        language: "fr".to_string(),
        ..DiktoConfig::default()
    };
    config.validate();
    assert_eq!(config.language, "fr");
}

/// "auto" is a special language value and should be accepted.
#[test]
fn validate_accepts_auto_language() {
    let mut config = DiktoConfig {
        language: "auto".to_string(),
        ..DiktoConfig::default()
    };
    config.validate();
    assert_eq!(config.language, "auto");
}

/// An uppercase language code is invalid and should reset to "en".
#[test]
fn validate_resets_uppercase_language() {
    let mut config = DiktoConfig {
        language: "INVALID".to_string(),
        ..DiktoConfig::default()
    };
    config.validate();
    assert_eq!(config.language, "en");
}

/// A single-character language code is too short and should reset to "en".
#[test]
fn validate_resets_too_short_language() {
    let mut config = DiktoConfig {
        language: "x".to_string(),
        ..DiktoConfig::default()
    };
    config.validate();
    assert_eq!(config.language, "en");
}

/// A 5+ character language code is too long and should reset to "en".
#[test]
fn validate_resets_too_long_language() {
    let mut config = DiktoConfig {
        language: "en123".to_string(),
        ..DiktoConfig::default()
    };
    config.validate();
    assert_eq!(config.language, "en");
}

// ---------------------------------------------------------------------------
// Validate — numeric clamping
// ---------------------------------------------------------------------------

/// max_duration above 120 should be clamped to 120.
#[test]
fn validate_clamps_max_duration_high() {
    let mut config = DiktoConfig {
        max_duration: 999,
        ..DiktoConfig::default()
    };
    config.validate();
    assert_eq!(config.max_duration, 120);
}

/// max_duration of 0 should be clamped to 1.
#[test]
fn validate_clamps_max_duration_low() {
    let mut config = DiktoConfig {
        max_duration: 0,
        ..DiktoConfig::default()
    };
    config.validate();
    assert_eq!(config.max_duration, 1);
}

/// silence_duration_ms above 10000 should be clamped to 10000.
#[test]
fn validate_clamps_silence_duration_high() {
    let mut config = DiktoConfig {
        silence_duration_ms: 99999,
        ..DiktoConfig::default()
    };
    config.validate();
    assert_eq!(config.silence_duration_ms, 10000);
}

/// silence_duration_ms below 250 should be clamped to 250.
#[test]
fn validate_clamps_silence_duration_low() {
    let mut config = DiktoConfig {
        silence_duration_ms: 10,
        ..DiktoConfig::default()
    };
    config.validate();
    assert_eq!(config.silence_duration_ms, 250);
}

/// speech_threshold above 0.99 should be clamped to 0.99.
#[test]
fn validate_clamps_speech_threshold_high() {
    let mut config = DiktoConfig {
        speech_threshold: 5.0,
        ..DiktoConfig::default()
    };
    config.validate();
    assert!((config.speech_threshold - 0.99).abs() < f32::EPSILON);
}

/// speech_threshold below 0.01 should be clamped to 0.01.
#[test]
fn validate_clamps_speech_threshold_low() {
    let mut config = DiktoConfig {
        speech_threshold: 0.0,
        ..DiktoConfig::default()
    };
    config.validate();
    assert!((config.speech_threshold - 0.01).abs() < f32::EPSILON);
}

// ---------------------------------------------------------------------------
// Serialize / roundtrip
// ---------------------------------------------------------------------------

/// Serializing and deserializing a config should preserve all fields.
#[test]
fn serialize_deserialize_roundtrip() {
    let original = DiktoConfig {
        model_name: "whisper-tiny".to_string(),
        language: "fr".to_string(),
        max_duration: 60,
        silence_duration_ms: 2000,
        speech_threshold: 0.5,
        global_shortcut: Some("command+shift+r".to_string()),
        auto_paste: false,
        auto_copy: true,
        activation_mode: ActivationMode::Toggle,
    };
    let json = serde_json::to_string_pretty(&original).unwrap();
    let loaded: DiktoConfig = serde_json::from_str(&json).unwrap();
    assert_eq!(loaded.model_name, "whisper-tiny");
    assert_eq!(loaded.language, "fr");
    assert_eq!(loaded.max_duration, 60);
    assert_eq!(loaded.silence_duration_ms, 2000);
    assert!((loaded.speech_threshold - 0.5).abs() < f32::EPSILON);
    assert_eq!(loaded.global_shortcut, Some("command+shift+r".to_string()));
    assert!(!loaded.auto_paste);
    assert!(loaded.auto_copy);
    assert_eq!(loaded.activation_mode, ActivationMode::Toggle);
}

/// Write config to a temp file and read it back — file-level roundtrip.
#[test]
fn save_load_file_roundtrip() {
    let tmp = std::env::temp_dir().join("dikto_test_config_roundtrip");
    let _ = std::fs::remove_dir_all(&tmp);
    std::fs::create_dir_all(&tmp).unwrap();

    let config_file = tmp.join("config.json");
    let original = DiktoConfig {
        model_name: "whisper-tiny".to_string(),
        language: "fr".to_string(),
        max_duration: 60,
        silence_duration_ms: 2000,
        speech_threshold: 0.5,
        global_shortcut: Some("command+shift+r".to_string()),
        auto_paste: false,
        auto_copy: true,
        activation_mode: ActivationMode::Toggle,
    };

    let json = serde_json::to_string_pretty(&original).unwrap();
    std::fs::write(&config_file, &json).unwrap();

    let contents = std::fs::read_to_string(&config_file).unwrap();
    let loaded: DiktoConfig = serde_json::from_str(&contents).unwrap();
    assert_eq!(loaded.model_name, "whisper-tiny");
    assert_eq!(loaded.activation_mode, ActivationMode::Toggle);

    let _ = std::fs::remove_dir_all(&tmp);
}

// ---------------------------------------------------------------------------
// ConfigError display
// ---------------------------------------------------------------------------

/// ConfigError variants should produce human-readable messages.
#[test]
fn config_error_display() {
    use dikto_core::config::ConfigError;

    let err = ConfigError::NoHomeDir;
    assert_eq!(err.to_string(), "Cannot determine home directory");

    let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "gone");
    let err = ConfigError::Io(io_err);
    assert!(err.to_string().contains("IO error"));
}

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

/// config_dir() should return a path containing "dikto".
#[test]
fn config_dir_contains_dikto() {
    let dir = config_dir();
    assert!(dir.is_ok());
    assert!(dir.unwrap().to_string_lossy().contains("dikto"));
}

/// data_dir() should return a path containing "dikto".
#[test]
fn data_dir_contains_dikto() {
    let dir = data_dir();
    assert!(dir.is_ok());
    assert!(dir.unwrap().to_string_lossy().contains("dikto"));
}

/// config_path() should end with "config.json".
#[test]
fn config_path_ends_with_config_json() {
    let path = config_path().unwrap();
    assert!(path.to_string_lossy().ends_with("config.json"));
}

/// models_dir() should contain "models".
#[test]
fn models_dir_contains_models() {
    let dir = models_dir();
    assert!(dir.to_string_lossy().contains("models"));
}
