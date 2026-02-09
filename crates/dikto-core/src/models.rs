use crate::config::models_dir;
use sha2::{Digest, Sha256};
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

/// ASR backend type for a model.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ModelBackend {
    Parakeet,
    Whisper,
}

/// A single file that is part of a model.
#[derive(Debug, Clone)]
pub struct ModelFile {
    pub filename: &'static str,
    pub url: &'static str,
    pub size_mb: u32,
    /// Expected SHA-256 hash (hex, lowercase). Empty string means skip verification.
    pub sha256: &'static str,
}

/// Model registry entry. A model is a directory containing multiple files.
#[derive(Debug, Clone)]
pub struct ModelInfo {
    pub name: &'static str,
    pub size_mb: u32,
    pub description: &'static str,
    pub files: &'static [ModelFile],
    pub backend: ModelBackend,
}

/// Hardcoded model registry.
pub const MODELS: &[ModelInfo] = &[
    ModelInfo {
        name: "parakeet-tdt-0.6b-v2",
        size_mb: 2520,
        description: "NVIDIA Parakeet TDT 0.6B v2 — high accuracy English ASR (1.69% WER)",
        backend: ModelBackend::Parakeet,
        files: &[
            ModelFile {
                filename: "encoder-model.onnx",
                url: concat!("https://huggingface.co/istupakov/parakeet-tdt-0.6b-v2-onnx/resolve/main", "/encoder-model.onnx"),
                size_mb: 42,
                sha256: "",
            },
            ModelFile {
                filename: "encoder-model.onnx.data",
                url: concat!("https://huggingface.co/istupakov/parakeet-tdt-0.6b-v2-onnx/resolve/main", "/encoder-model.onnx.data"),
                size_mb: 2440,
                sha256: "",
            },
            ModelFile {
                filename: "decoder_joint-model.onnx",
                url: concat!("https://huggingface.co/istupakov/parakeet-tdt-0.6b-v2-onnx/resolve/main", "/decoder_joint-model.onnx"),
                size_mb: 36,
                sha256: "",
            },
            ModelFile {
                filename: "vocab.txt",
                url: concat!("https://huggingface.co/istupakov/parakeet-tdt-0.6b-v2-onnx/resolve/main", "/vocab.txt"),
                size_mb: 1,
                sha256: "",
            },
        ],
    },
    ModelInfo {
        name: "parakeet-tdt-0.6b-v3",
        size_mb: 2560,
        description: "NVIDIA Parakeet TDT 0.6B v3 — 25 EU languages, 6.34% avg WER",
        backend: ModelBackend::Parakeet,
        files: &[
            ModelFile {
                filename: "encoder-model.onnx",
                url: concat!("https://huggingface.co/istupakov/parakeet-tdt-0.6b-v3-onnx/resolve/main", "/encoder-model.onnx"),
                size_mb: 42,
                sha256: "",
            },
            ModelFile {
                filename: "encoder-model.onnx.data",
                url: concat!("https://huggingface.co/istupakov/parakeet-tdt-0.6b-v3-onnx/resolve/main", "/encoder-model.onnx.data"),
                size_mb: 2440,
                sha256: "",
            },
            ModelFile {
                filename: "decoder_joint-model.onnx",
                url: concat!("https://huggingface.co/istupakov/parakeet-tdt-0.6b-v3-onnx/resolve/main", "/decoder_joint-model.onnx"),
                size_mb: 73,
                sha256: "",
            },
            ModelFile {
                filename: "vocab.txt",
                url: concat!("https://huggingface.co/istupakov/parakeet-tdt-0.6b-v3-onnx/resolve/main", "/vocab.txt"),
                size_mb: 1,
                sha256: "",
            },
        ],
    },
    ModelInfo {
        name: "whisper-tiny",
        size_mb: 75,
        description: "Whisper Tiny — fast, 99 languages, ~75 MB",
        backend: ModelBackend::Whisper,
        files: &[ModelFile {
            filename: "ggml-tiny.bin",
            url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
            size_mb: 75,
            sha256: "",
        }],
    },
    ModelInfo {
        name: "whisper-small",
        size_mb: 460,
        description: "Whisper Small — balanced accuracy & speed, 99 languages, ~460 MB",
        backend: ModelBackend::Whisper,
        files: &[ModelFile {
            filename: "ggml-small.bin",
            url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin",
            size_mb: 460,
            sha256: "",
        }],
    },
    ModelInfo {
        name: "whisper-large-v3-turbo",
        size_mb: 1600,
        description: "Whisper Large v3 Turbo — highest accuracy, 99 languages, ~1.6 GB",
        backend: ModelBackend::Whisper,
        files: &[ModelFile {
            filename: "ggml-large-v3-turbo.bin",
            url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin",
            size_mb: 1600,
            sha256: "",
        }],
    },
    ModelInfo {
        name: "distil-whisper-large-v3",
        size_mb: 1520,
        description: "Distil-Whisper Large v3 — 6x faster Whisper, 99 languages, ~1.5 GB",
        backend: ModelBackend::Whisper,
        files: &[ModelFile {
            filename: "ggml-distil-large-v3.bin",
            url: "https://huggingface.co/distil-whisper/distil-large-v3-ggml/resolve/main/ggml-distil-large-v3.bin",
            size_mb: 1520,
            sha256: "",
        }],
    },
];

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
pub async fn download_model<F>(name: &str, on_progress: F) -> Result<PathBuf, ModelError>
where
    F: Fn(u64, u64) + Send + 'static,
{
    let model = find_model(name).ok_or_else(|| {
        let available = MODELS.iter().map(|m| m.name).collect::<Vec<_>>().join(", ");
        ModelError::NotFound(name.to_string(), available)
    })?;

    let dir = models_dir().join(name);
    std::fs::create_dir_all(&dir)?;

    // Calculate total size and already-downloaded bytes
    let total_bytes: u64 = model
        .files
        .iter()
        .map(|f| f.size_mb as u64 * 1024 * 1024)
        .sum();
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

        // Use a closure to ensure temp file cleanup on any error
        let download_result: Result<(), ModelError> = async {
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

            // Verify SHA-256 hash if provided
            if !file.sha256.is_empty() {
                let temp_path = temp_dest.clone();
                let expected_hash = file.sha256.to_string();
                let hash_ok = tokio::task::spawn_blocking(move || {
                    verify_file_sha256(&temp_path, &expected_hash)
                })
                .await
                .map_err(|e| ModelError::DownloadFailed(format!("Hash task failed: {e}")))?;

                if !hash_ok {
                    return Err(ModelError::DownloadFailed(format!(
                        "SHA-256 mismatch for {}",
                        file.filename
                    )));
                }
                info!("SHA-256 verified for {}", file.filename);
            } else {
                // Fallback: verify file size (within 10% of expected)
                let actual_size = tokio::fs::metadata(&temp_dest)
                    .await
                    .map_err(ModelError::Io)?
                    .len();
                let expected_size = file.size_mb as u64 * 1024 * 1024;
                let tolerance = expected_size / 10;
                if actual_size < expected_size.saturating_sub(tolerance) {
                    return Err(ModelError::DownloadFailed(format!(
                        "Size mismatch for {}: expected ~{} MB, got {} bytes",
                        file.filename, file.size_mb, actual_size
                    )));
                }
            }

            tokio::fs::rename(&temp_dest, &dest)
                .await
                .map_err(ModelError::Io)?;

            Ok(())
        }
        .await;

        // Clean up temp file on any error
        if let Err(e) = download_result {
            let _ = tokio::fs::remove_file(&temp_dest).await;
            return Err(e);
        }

        info!("Downloaded {}", file.filename);
    }

    info!(
        "All files for model '{}' downloaded to {}",
        name,
        dir.display()
    );
    Ok(dir)
}

/// Verify the SHA-256 hash of a file.
fn verify_file_sha256(path: &std::path::Path, expected_hex: &str) -> bool {
    let Ok(mut file) = std::fs::File::open(path) else {
        return false;
    };
    let mut hasher = Sha256::new();
    if std::io::copy(&mut file, &mut hasher).is_err() {
        return false;
    }
    let actual = format!("{:x}", hasher.finalize());
    actual == expected_hex
}

/// Delete a downloaded model (removes the entire model directory).
pub fn delete_model(name: &str) -> Result<(), ModelError> {
    let Some(_) = find_model(name) else {
        let available = MODELS.iter().map(|m| m.name).collect::<Vec<_>>().join(", ");
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
        assert_eq!(MODELS.len(), 6);
        assert_eq!(MODELS[0].name, "parakeet-tdt-0.6b-v2");
        assert_eq!(MODELS[0].files.len(), 4);
        assert_eq!(MODELS[0].backend, ModelBackend::Parakeet);
        assert_eq!(MODELS[1].name, "parakeet-tdt-0.6b-v3");
        assert_eq!(MODELS[1].files.len(), 4);
        assert_eq!(MODELS[1].backend, ModelBackend::Parakeet);
        assert_eq!(MODELS[2].name, "whisper-tiny");
        assert_eq!(MODELS[2].backend, ModelBackend::Whisper);
        assert_eq!(MODELS[2].files.len(), 1);
        assert!(find_model("distil-whisper-large-v3").is_some());
    }

    #[test]
    fn test_model_path_is_directory() {
        let path = model_path("parakeet-tdt-0.6b-v2").unwrap();
        assert!(path.to_string_lossy().ends_with("parakeet-tdt-0.6b-v2"));
    }

    #[test]
    fn test_all_model_urls_are_https() {
        for model in MODELS {
            for file in model.files {
                assert!(
                    file.url.starts_with("https://"),
                    "Model file {} in {} has non-HTTPS URL: {}",
                    file.filename,
                    model.name,
                    file.url
                );
            }
        }
    }

    #[test]
    fn test_model_size_estimates_reasonable() {
        for model in MODELS {
            assert!(model.size_mb > 0, "Model {} has zero size", model.name);
            for file in model.files {
                assert!(
                    file.size_mb > 0,
                    "File {} in {} has zero size",
                    file.filename,
                    model.name
                );
            }
        }
    }

    #[test]
    fn test_sha256_hashes_valid_hex() {
        for model in MODELS {
            for file in model.files {
                if !file.sha256.is_empty() {
                    assert_eq!(
                        file.sha256.len(),
                        64,
                        "SHA-256 for {} in {} is not 64 hex chars",
                        file.filename,
                        model.name
                    );
                    assert!(
                        file.sha256.chars().all(|c| c.is_ascii_hexdigit()),
                        "SHA-256 for {} in {} contains non-hex chars",
                        file.filename,
                        model.name
                    );
                }
            }
        }
    }

    #[test]
    fn test_verify_file_sha256() {
        use std::io::Write;
        let tmp = std::env::temp_dir().join("dikto_sha256_test");
        let mut f = std::fs::File::create(&tmp).unwrap();
        f.write_all(b"hello world").unwrap();
        drop(f);

        // SHA-256 of "hello world"
        let expected = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9";
        assert!(verify_file_sha256(&tmp, expected));
        assert!(!verify_file_sha256(
            &tmp,
            "0000000000000000000000000000000000000000000000000000000000000000"
        ));

        let _ = std::fs::remove_file(&tmp);
    }
}
