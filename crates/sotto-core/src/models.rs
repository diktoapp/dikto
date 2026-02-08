use crate::config::models_dir;
use std::path::PathBuf;
use thiserror::Error;
use tracing::{info, warn};

#[derive(Debug, Error)]
pub enum ModelError {
    #[error("Model '{0}' not found. Available: {1}")]
    NotFound(String, String),
    #[error("Download failed: {0}")]
    DownloadFailed(String),
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),
}

/// A single file that is part of a model.
#[derive(Debug, Clone)]
pub struct ModelFile {
    pub filename: &'static str,
    pub url: &'static str,
    pub size_mb: u32,
}

/// Model registry entry. A model is a directory containing multiple files.
#[derive(Debug, Clone)]
pub struct ModelInfo {
    pub name: &'static str,
    pub size_mb: u32,
    pub description: &'static str,
    pub files: &'static [ModelFile],
}

/// Hardcoded model registry — Parakeet TDT models.
pub const MODELS: &[ModelInfo] = &[ModelInfo {
    name: "parakeet-tdt-0.6b-v2",
    size_mb: 2520,
    description: "NVIDIA Parakeet TDT 0.6B v2 — high accuracy English ASR (1.69% WER)",
    files: &[
        ModelFile {
            filename: "encoder-model.onnx",
            url: concat!("https://huggingface.co/istupakov/parakeet-tdt-0.6b-v2-onnx/resolve/main", "/encoder-model.onnx"),
            size_mb: 42,
        },
        ModelFile {
            filename: "encoder-model.onnx.data",
            url: concat!("https://huggingface.co/istupakov/parakeet-tdt-0.6b-v2-onnx/resolve/main", "/encoder-model.onnx.data"),
            size_mb: 2440,
        },
        ModelFile {
            filename: "decoder_joint-model.onnx",
            url: concat!("https://huggingface.co/istupakov/parakeet-tdt-0.6b-v2-onnx/resolve/main", "/decoder_joint-model.onnx"),
            size_mb: 36,
        },
        ModelFile {
            filename: "vocab.txt",
            url: concat!("https://huggingface.co/istupakov/parakeet-tdt-0.6b-v2-onnx/resolve/main", "/vocab.txt"),
            size_mb: 1,
        },
    ],
}];

/// Look up model info by name.
pub fn find_model(name: &str) -> Option<&'static ModelInfo> {
    MODELS.iter().find(|m| m.name == name)
}

/// Get the local directory path for a model.
pub fn model_path(name: &str) -> Option<PathBuf> {
    find_model(name).map(|_| models_dir().join(name))
}

/// Check if all files of a model are downloaded.
pub fn is_model_downloaded(name: &str) -> bool {
    let Some(model) = find_model(name) else {
        return false;
    };
    let dir = models_dir().join(name);
    model.files.iter().all(|f| dir.join(f.filename).exists())
}

/// List all models with their download status.
pub fn list_models() -> Vec<(ModelInfo, bool)> {
    MODELS
        .iter()
        .map(|m| (m.clone(), is_model_downloaded(m.name)))
        .collect()
}

/// Download a model with progress callback.
/// `on_progress` receives (bytes_downloaded, total_bytes).
pub async fn download_model<F>(
    name: &str,
    on_progress: F,
) -> Result<PathBuf, ModelError>
where
    F: Fn(u64, u64) + Send + 'static,
{
    let model = find_model(name).ok_or_else(|| {
        let available = MODELS
            .iter()
            .map(|m| m.name)
            .collect::<Vec<_>>()
            .join(", ");
        ModelError::NotFound(name.to_string(), available)
    })?;

    let dir = models_dir().join(name);
    std::fs::create_dir_all(&dir)?;

    // Calculate total size and already-downloaded bytes
    let total_bytes: u64 = model.files.iter().map(|f| f.size_mb as u64 * 1024 * 1024).sum();
    let mut cumulative_downloaded: u64 = 0;

    for file in model.files {
        let dest = dir.join(file.filename);

        if dest.exists() {
            // Count existing file size towards progress
            let existing_size = std::fs::metadata(&dest).map(|m| m.len()).unwrap_or(0);
            cumulative_downloaded += existing_size;
            on_progress(cumulative_downloaded, total_bytes);
            info!("File {} already exists, skipping", file.filename);
            continue;
        }

        info!(
            "Downloading {} ({} MB) from {}",
            file.filename, file.size_mb, file.url
        );

        let response = reqwest::get(file.url).await?;

        if !response.status().is_success() {
            return Err(ModelError::DownloadFailed(format!(
                "HTTP {} for {}",
                response.status(),
                file.filename
            )));
        }

        let temp_dest = dir.join(format!("{}.downloading", file.filename));

        use futures::StreamExt;
        let mut stream = response.bytes_stream();
        let mut out = tokio::fs::File::create(&temp_dest)
            .await
            .map_err(ModelError::Io)?;

        use tokio::io::AsyncWriteExt;
        while let Some(chunk) = stream.next().await {
            let chunk = chunk?;
            out.write_all(&chunk).await.map_err(ModelError::Io)?;
            cumulative_downloaded += chunk.len() as u64;
            on_progress(cumulative_downloaded, total_bytes);
        }
        out.flush().await.map_err(ModelError::Io)?;
        drop(out);

        tokio::fs::rename(&temp_dest, &dest)
            .await
            .map_err(ModelError::Io)?;

        info!("Downloaded {}", file.filename);
    }

    info!("All files for model '{}' downloaded to {}", name, dir.display());
    Ok(dir)
}

/// Delete a downloaded model (removes the entire model directory).
pub fn delete_model(name: &str) -> Result<(), ModelError> {
    let Some(_) = find_model(name) else {
        let available = MODELS
            .iter()
            .map(|m| m.name)
            .collect::<Vec<_>>()
            .join(", ");
        return Err(ModelError::NotFound(name.to_string(), available));
    };

    let dir = models_dir().join(name);
    if dir.exists() {
        std::fs::remove_dir_all(&dir)?;
        info!("Deleted model {} at {}", name, dir.display());
    } else {
        warn!("Model {} not found at {}", name, dir.display());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_find_model() {
        assert!(find_model("parakeet-tdt-0.6b-v2").is_some());
        assert!(find_model("nonexistent").is_none());
    }

    #[test]
    fn test_model_registry() {
        assert_eq!(MODELS.len(), 1);
        assert_eq!(MODELS[0].name, "parakeet-tdt-0.6b-v2");
        assert_eq!(MODELS[0].files.len(), 4);
    }

    #[test]
    fn test_model_path_is_directory() {
        let path = model_path("parakeet-tdt-0.6b-v2").unwrap();
        assert!(path.to_string_lossy().ends_with("parakeet-tdt-0.6b-v2"));
    }
}
