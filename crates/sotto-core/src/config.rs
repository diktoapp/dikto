use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tracing::warn;

/// Activation mode for the global hotkey.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, uniffi::Enum)]
#[serde(rename_all = "lowercase")]
pub enum ActivationMode {
    Toggle,
    Hold,
}

impl Default for ActivationMode {
    fn default() -> Self {
        ActivationMode::Hold
    }
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
    let key_count = parts.iter().filter(|p| !VALID_MODIFIERS.contains(p)).count();
    modifier_count >= 1 && key_count == 1
}

/// Configuration for Sotto, backward-compatible with v1 paths.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct SottoConfig {
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

impl Default for SottoConfig {
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

impl SottoConfig {
    /// Clamp all numeric fields to safe ranges and validate shortcut.
    pub fn validate(&mut self) {
        self.max_duration = self.max_duration.clamp(1, 120);
        self.silence_duration_ms = self.silence_duration_ms.clamp(250, 10000);
        self.speech_threshold = self.speech_threshold.clamp(0.01, 0.99);

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

/// Returns the config directory path: ~/.config/sotto/
pub fn config_dir() -> PathBuf {
    dirs::home_dir()
        .expect("Cannot determine home directory")
        .join(".config/sotto")
}

/// Returns the data directory path: ~/.local/share/sotto/
pub fn data_dir() -> PathBuf {
    dirs::home_dir()
        .expect("Cannot determine home directory")
        .join(".local/share/sotto")
}

/// Returns the models directory path: ~/.local/share/sotto/models/
pub fn models_dir() -> PathBuf {
    data_dir().join("models")
}

/// Returns the config file path: ~/.config/sotto/config.json
pub fn config_path() -> PathBuf {
    config_dir().join("config.json")
}

/// Load config from disk, with env var overrides for backward compatibility.
/// Migration: existing config files without `activation_mode` get Toggle (preserves behavior).
/// New installs get Hold (push-to-talk).
pub fn load_config() -> SottoConfig {
    let path = config_path();
    let mut config = if path.exists() {
        match std::fs::read_to_string(&path) {
            Ok(contents) => {
                // Check if existing config has activation_mode before deserializing
                let has_activation_mode = serde_json::from_str::<serde_json::Value>(&contents)
                    .ok()
                    .and_then(|v| v.get("activation_mode").cloned())
                    .is_some();

                match serde_json::from_str::<SottoConfig>(&contents) {
                    Ok(mut c) => {
                        // Migration: existing config without activation_mode → Toggle
                        if !has_activation_mode {
                            c.activation_mode = ActivationMode::Toggle;
                        }
                        c
                    }
                    Err(e) => {
                        warn!("Failed to parse config at {}: {e}", path.display());
                        SottoConfig::default()
                    }
                }
            }
            Err(e) => {
                warn!("Failed to read config at {}: {e}", path.display());
                SottoConfig::default()
            }
        }
    } else {
        SottoConfig::default()
    };

    // Env var overrides (backward-compatible with v1)
    if let Ok(v) = std::env::var("SOTTO_MODEL") {
        config.model_name = v;
    }
    if let Ok(v) = std::env::var("SOTTO_LANGUAGE") {
        config.language = v;
    }
    if let Ok(v) = std::env::var("SOTTO_MAX_DURATION") {
        if let Ok(n) = v.parse() {
            config.max_duration = n;
        }
    }

    config.validate();
    config
}

/// Save config to disk. Values are validated (clamped) before saving.
pub fn save_config(config: &SottoConfig) -> Result<(), std::io::Error> {
    let mut config = config.clone();
    config.validate();
    let path = config_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(&config).map_err(std::io::Error::other)?;
    std::fs::write(&path, json)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = SottoConfig::default();
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
        let config: SottoConfig = serde_json::from_str(json).unwrap();
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
        let mut config: SottoConfig = serde_json::from_str(json).unwrap();
        if !has_activation_mode {
            config.activation_mode = ActivationMode::Toggle;
        }
        // Existing users without the field → Toggle (preserves their current toggle behavior)
        assert_eq!(config.activation_mode, ActivationMode::Toggle);
    }

    #[test]
    fn test_activation_mode_serialization() {
        let json = r#"{"activation_mode":"hold"}"#;
        let config: SottoConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.activation_mode, ActivationMode::Hold);

        let json = r#"{"activation_mode":"toggle"}"#;
        let config: SottoConfig = serde_json::from_str(json).unwrap();
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
        let mut config = SottoConfig::default();
        config.global_shortcut = Some("just-a-key".to_string());
        config.validate();
        assert_eq!(config.global_shortcut, Some("option+r".to_string()));
    }

    #[test]
    fn test_validate_resets_none_shortcut() {
        let mut config = SottoConfig::default();
        config.global_shortcut = None;
        config.validate();
        assert_eq!(config.global_shortcut, Some("option+r".to_string()));
    }

    #[test]
    fn test_models_dir() {
        let dir = models_dir();
        assert!(dir.to_string_lossy().contains("sotto"));
        assert!(dir.to_string_lossy().contains("models"));
    }
}
