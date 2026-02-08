use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use tracing::warn;

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
    #[serde(default)]
    pub global_shortcut: Option<String>,
    #[serde(default = "default_true")]
    pub auto_paste: bool,
    #[serde(default = "default_true")]
    pub auto_copy: bool,
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

impl Default for SottoConfig {
    fn default() -> Self {
        Self {
            model_name: default_model_name(),
            language: default_language(),
            max_duration: default_max_duration(),
            silence_duration_ms: default_silence_duration_ms(),
            speech_threshold: default_speech_threshold(),
            global_shortcut: None,
            auto_paste: true,
            auto_copy: true,
        }
    }
}

/// Returns the config directory path: ~/.config/sotto/
pub fn config_dir() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join(".config/sotto")
}

/// Returns the data directory path: ~/.local/share/sotto/
pub fn data_dir() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
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
pub fn load_config() -> SottoConfig {
    let path = config_path();
    let mut config = if path.exists() {
        match std::fs::read_to_string(&path) {
            Ok(contents) => match serde_json::from_str::<SottoConfig>(&contents) {
                Ok(c) => c,
                Err(e) => {
                    warn!("Failed to parse config at {}: {e}", path.display());
                    SottoConfig::default()
                }
            },
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

    config
}

/// Save config to disk.
pub fn save_config(config: &SottoConfig) -> Result<(), std::io::Error> {
    let path = config_path();
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string_pretty(config).map_err(|e| {
        std::io::Error::new(std::io::ErrorKind::Other, e)
    })?;
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
    }

    #[test]
    fn test_models_dir() {
        let dir = models_dir();
        assert!(dir.to_string_lossy().contains("sotto"));
        assert!(dir.to_string_lossy().contains("models"));
    }
}
