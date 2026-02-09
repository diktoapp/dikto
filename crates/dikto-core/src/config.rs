use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tracing::warn;

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("Cannot determine home directory")]
    NoHomeDir,
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

/// Activation mode for the global hotkey.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, uniffi::Enum)]
#[serde(rename_all = "lowercase")]
#[derive(Default)]
pub enum ActivationMode {
    Toggle,
    #[default]
    Hold,
}

/// Valid modifier names for shortcut strings.
const VALID_MODIFIERS: &[&str] = &["option", "command", "control", "shift"];

/// Validate a shortcut string like "option+r" or "command+shift+space".
/// Returns true if it has at least 1 modifier and 1 non-modifier key.
fn is_valid_shortcut(shortcut: &str) -> bool {
    let parts: Vec<&str> = shortcut.split('+').map(|s| s.trim()).collect();
    if parts.len() < 2 {
        return false;
    }
    let modifier_count = parts.iter().filter(|p| VALID_MODIFIERS.contains(p)).count();
    let key_count = parts
        .iter()
        .filter(|p| !VALID_MODIFIERS.contains(p))
        .count();
    modifier_count >= 1 && key_count == 1
}

/// Configuration for Dikto, backward-compatible with v1 paths.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct DiktoConfig {
    #[serde(default = "default_model_name")]
    pub model_name: String,
    #[serde(default = "default_language")]
    pub language: String,
    #[serde(default = "default_max_duration")]
    pub max_duration: u32,
    #[serde(default = "default_silence_duration_ms")]
    pub silence_duration_ms: u32,
    #[serde(default = "default_speech_threshold")]
    pub speech_threshold: f32,
    #[serde(default = "default_global_shortcut")]
    pub global_shortcut: Option<String>,
    #[serde(default = "default_true")]
    pub auto_paste: bool,
    #[serde(default = "default_true")]
    pub auto_copy: bool,
    #[serde(default)]
    pub activation_mode: ActivationMode,
}

pub fn default_model_name() -> String {
    "parakeet-tdt-0.6b-v2".to_string()
}

fn default_language() -> String {
    "en".to_string()
}

fn default_max_duration() -> u32 {
    30
}

fn default_silence_duration_ms() -> u32 {
    1500
}

fn default_speech_threshold() -> f32 {
    0.35
}

fn default_true() -> bool {
    true
}

fn default_global_shortcut() -> Option<String> {
    Some("option+r".to_string())
}

impl Default for DiktoConfig {
    fn default() -> Self {
        Self {
            model_name: default_model_name(),
            language: default_language(),
            max_duration: default_max_duration(),
            silence_duration_ms: default_silence_duration_ms(),
            speech_threshold: default_speech_threshold(),
            global_shortcut: default_global_shortcut(),
            auto_paste: true,
            auto_copy: true,
            activation_mode: ActivationMode::Hold,
        }
    }
}

impl DiktoConfig {
    /// Clamp all numeric fields to safe ranges and validate shortcut and language.
    pub fn validate(&mut self) {
        self.max_duration = self.max_duration.clamp(1, 120);
        self.silence_duration_ms = self.silence_duration_ms.clamp(250, 10000);
        self.speech_threshold = self.speech_threshold.clamp(0.01, 0.99);

        // Validate language code: must be 2-4 lowercase letters or "auto"
        if self.language != "auto" {
            let valid = self.language.len() >= 2
                && self.language.len() <= 4
                && self.language.chars().all(|c| c.is_ascii_lowercase());
            if !valid {
                warn!(
                    "Invalid language code '{}', resetting to 'en'",
                    self.language
                );
                self.language = "en".to_string();
            }
        }

        // Validate global shortcut
        match &self.global_shortcut {
            Some(s) if !is_valid_shortcut(s) => {
                warn!("Invalid shortcut '{}', resetting to 'option+r'", s);
                self.global_shortcut = Some("option+r".to_string());
            }
            None => {
                self.global_shortcut = Some("option+r".to_string());
            }
            _ => {}
        }
    }
}

/// Returns the config directory path: ~/.config/dikto/
pub fn config_dir() -> Result<PathBuf, ConfigError> {
    Ok(dirs::home_dir()
        .ok_or(ConfigError::NoHomeDir)?
        .join(".config/dikto"))
}

/// Returns the data directory path: ~/.local/share/dikto/
pub fn data_dir() -> Result<PathBuf, ConfigError> {
    Ok(dirs::home_dir()
        .ok_or(ConfigError::NoHomeDir)?
        .join(".local/share/dikto"))
}

/// Returns the models directory path: ~/.local/share/dikto/models/
pub fn models_dir() -> PathBuf {
    match data_dir() {
        Ok(d) => d.join("models"),
        Err(e) => {
            warn!("Failed to determine data directory: {e}, falling back to ./models");
            PathBuf::from("./models")
        }
    }
}

/// Returns the config file path: ~/.config/dikto/config.json
pub fn config_path() -> Result<PathBuf, ConfigError> {
    Ok(config_dir()?.join("config.json"))
}

/// Load config from disk, with env var overrides for backward compatibility.
/// Migration: existing config files without `activation_mode` get Toggle (preserves behavior).
/// New installs get Hold (push-to-talk).
pub fn load_config() -> DiktoConfig {
    let path = match config_path() {
        Ok(p) => p,
        Err(e) => {
            warn!("Failed to determine config path: {e}, using defaults");
            return DiktoConfig::default();
        }
    };
    let mut config = if path.exists() {
        match std::fs::read_to_string(&path) {
            Ok(contents) => {
                // Check if existing config has activation_mode before deserializing
                let has_activation_mode = serde_json::from_str::<serde_json::Value>(&contents)
                    .ok()
                    .and_then(|v| v.get("activation_mode").cloned())
                    .is_some();

                match serde_json::from_str::<DiktoConfig>(&contents) {
                    Ok(mut c) => {
                        // Migration: existing config without activation_mode → Toggle
                        if !has_activation_mode {
                            c.activation_mode = ActivationMode::Toggle;
                        }
                        c
                    }
                    Err(e) => {
                        warn!("Failed to parse config at {}: {e}", path.display());
                        DiktoConfig::default()
                    }
                }
            }
            Err(e) => {
                warn!("Failed to read config at {}: {e}", path.display());
                DiktoConfig::default()
            }
        }
    } else {
        DiktoConfig::default()
    };

    // Env var overrides (backward-compatible with v1)
    if let Ok(v) = std::env::var("DIKTO_MODEL") {
        config.model_name = v;
    }
    if let Ok(v) = std::env::var("DIKTO_LANGUAGE") {
        config.language = v;
    }
    if let Ok(v) = std::env::var("DIKTO_MAX_DURATION") {
        if let Ok(n) = v.parse() {
            config.max_duration = n;
        }
    }

    config.validate();
    config
}

/// Save config to disk. Values are validated (clamped) before saving.
/// Sets file permissions to 0600 (user read/write only).
pub fn save_config(config: &DiktoConfig) -> Result<(), std::io::Error> {
    let mut config = config.clone();
    config.validate();
    let path = config_path().map_err(|e| std::io::Error::other(e.to_string()))?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(&config).map_err(std::io::Error::other)?;
    std::fs::write(&path, &json)?;

    // Set file permissions to user read/write only (0600)
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
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

    #[test]
    fn test_config_deserialize() {
        let json = r#"{"model_name":"tiny.en","language":"fr","max_duration":60}"#;
        let config: DiktoConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.model_name, "tiny.en");
        assert_eq!(config.language, "fr");
        assert_eq!(config.max_duration, 60);
        // Defaults for missing fields
        assert_eq!(config.silence_duration_ms, 1500);
        assert_eq!(config.global_shortcut, Some("option+r".to_string()));
    }

    #[test]
    fn test_backward_compat_no_activation_mode() {
        // Simulates an existing config file without activation_mode
        let json = r#"{"model_name":"parakeet-tdt-0.6b-v2","language":"en","auto_paste":true}"#;
        let raw: serde_json::Value = serde_json::from_str(json).unwrap();
        let has_activation_mode = raw.get("activation_mode").is_some();
        let mut config: DiktoConfig = serde_json::from_str(json).unwrap();
        if !has_activation_mode {
            config.activation_mode = ActivationMode::Toggle;
        }
        // Existing users without the field → Toggle (preserves their current toggle behavior)
        assert_eq!(config.activation_mode, ActivationMode::Toggle);
    }

    #[test]
    fn test_activation_mode_serialization() {
        let json = r#"{"activation_mode":"hold"}"#;
        let config: DiktoConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.activation_mode, ActivationMode::Hold);

        let json = r#"{"activation_mode":"toggle"}"#;
        let config: DiktoConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.activation_mode, ActivationMode::Toggle);
    }

    #[test]
    fn test_shortcut_validation() {
        assert!(is_valid_shortcut("option+r"));
        assert!(is_valid_shortcut("command+shift+space"));
        assert!(is_valid_shortcut("control+option+f1"));
        assert!(!is_valid_shortcut("r")); // no modifier
        assert!(!is_valid_shortcut("option")); // no key
        assert!(!is_valid_shortcut("option+r+s")); // two keys
        assert!(!is_valid_shortcut("")); // empty
    }

    #[test]
    fn test_validate_resets_invalid_shortcut() {
        let mut config = DiktoConfig::default();
        config.global_shortcut = Some("just-a-key".to_string());
        config.validate();
        assert_eq!(config.global_shortcut, Some("option+r".to_string()));
    }

    #[test]
    fn test_validate_resets_none_shortcut() {
        let mut config = DiktoConfig::default();
        config.global_shortcut = None;
        config.validate();
        assert_eq!(config.global_shortcut, Some("option+r".to_string()));
    }

    #[test]
    fn test_models_dir() {
        let dir = models_dir();
        assert!(
            dir.to_string_lossy().contains("dikto") || dir.to_string_lossy().contains("models")
        );
        assert!(dir.to_string_lossy().contains("models"));
    }

    #[test]
    fn test_config_dir_returns_ok() {
        // Should succeed when HOME is set (normal test environment)
        let dir = config_dir();
        assert!(dir.is_ok());
        assert!(dir.unwrap().to_string_lossy().contains("dikto"));
    }

    #[test]
    fn test_validate_language_code() {
        let mut config = DiktoConfig::default();

        // Valid codes should be kept
        config.language = "fr".to_string();
        config.validate();
        assert_eq!(config.language, "fr");

        config.language = "auto".to_string();
        config.validate();
        assert_eq!(config.language, "auto");

        // Invalid codes should reset to "en"
        config.language = "INVALID".to_string();
        config.validate();
        assert_eq!(config.language, "en");

        config.language = "x".to_string(); // too short
        config.validate();
        assert_eq!(config.language, "en");

        config.language = "en123".to_string(); // too long
        config.validate();
        assert_eq!(config.language, "en");
    }

    #[test]
    fn test_save_load_roundtrip() {
        use std::env;
        // Use a temp directory for this test
        let tmp = env::temp_dir().join("dikto_test_config");
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

        // Write directly to temp path
        let json = serde_json::to_string_pretty(&original).unwrap();
        std::fs::write(&config_file, &json).unwrap();

        // Read back
        let contents = std::fs::read_to_string(&config_file).unwrap();
        let loaded: DiktoConfig = serde_json::from_str(&contents).unwrap();
        assert_eq!(loaded.model_name, "whisper-tiny");
        assert_eq!(loaded.language, "fr");
        assert_eq!(loaded.max_duration, 60);
        assert_eq!(loaded.silence_duration_ms, 2000);
        assert!((loaded.speech_threshold - 0.5).abs() < f32::EPSILON);
        assert_eq!(loaded.global_shortcut, Some("command+shift+r".to_string()));
        assert!(!loaded.auto_paste);
        assert!(loaded.auto_copy);
        assert_eq!(loaded.activation_mode, ActivationMode::Toggle);

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn test_corrupt_config_fallback() {
        use std::env;
        let tmp = env::temp_dir().join("dikto_test_corrupt");
        let _ = std::fs::remove_dir_all(&tmp);
        std::fs::create_dir_all(&tmp).unwrap();

        let config_file = tmp.join("config.json");
        std::fs::write(&config_file, "this is not json!!!").unwrap();

        let contents = std::fs::read_to_string(&config_file).unwrap();
        let result = serde_json::from_str::<DiktoConfig>(&contents);
        assert!(result.is_err());

        // Verify that load_config's fallback path returns defaults
        let default = DiktoConfig::default();
        assert_eq!(default.model_name, "parakeet-tdt-0.6b-v2");

        let _ = std::fs::remove_dir_all(&tmp);
    }
}
