// Tests for dikto_core::models — model registry, file lookup, path resolution,
// URL validation, SHA-256 verification, and download/delete error paths.

use dikto_core::models::{
    delete_model, find_model, is_model_downloaded, list_models, model_path, verify_file_sha256,
    ModelBackend, ModelError, MODELS,
};
use std::collections::HashSet;

// ---------------------------------------------------------------------------
// find_model
// ---------------------------------------------------------------------------

/// find_model should return Some for the default Parakeet v2 model.
#[test]
fn find_model_parakeet_v2_exists() {
    assert!(find_model("parakeet-tdt-0.6b-v2").is_some());
}

/// find_model should return Some for Parakeet v3.
#[test]
fn find_model_parakeet_v3_exists() {
    assert!(find_model("parakeet-tdt-0.6b-v3").is_some());
}

/// find_model should return Some for whisper-tiny.
#[test]
fn find_model_whisper_tiny_exists() {
    assert!(find_model("whisper-tiny").is_some());
}

/// find_model should return Some for whisper-small.
#[test]
fn find_model_whisper_small_exists() {
    assert!(find_model("whisper-small").is_some());
}

/// find_model should return Some for whisper-large-v3-turbo.
#[test]
fn find_model_whisper_large_v3_turbo_exists() {
    assert!(find_model("whisper-large-v3-turbo").is_some());
}

/// find_model should return Some for distil-whisper-large-v3.
#[test]
fn find_model_distil_whisper_exists() {
    assert!(find_model("distil-whisper-large-v3").is_some());
}

/// find_model should return None for a nonexistent model name.
#[test]
fn find_model_nonexistent_returns_none() {
    assert!(find_model("nonexistent").is_none());
}

// ---------------------------------------------------------------------------
// Registry structure
// ---------------------------------------------------------------------------

/// The model registry should contain exactly 6 models.
#[test]
fn registry_has_six_models() {
    assert_eq!(MODELS.len(), 6);
}

/// The first model should be parakeet-tdt-0.6b-v2 with Parakeet backend and 4 files.
#[test]
fn registry_first_model_is_parakeet_v2() {
    assert_eq!(MODELS[0].name, "parakeet-tdt-0.6b-v2");
    assert_eq!(MODELS[0].files.len(), 4);
    assert_eq!(MODELS[0].backend, ModelBackend::Parakeet);
}

/// The second model should be parakeet-tdt-0.6b-v3 with Parakeet backend and 4 files.
#[test]
fn registry_second_model_is_parakeet_v3() {
    assert_eq!(MODELS[1].name, "parakeet-tdt-0.6b-v3");
    assert_eq!(MODELS[1].files.len(), 4);
    assert_eq!(MODELS[1].backend, ModelBackend::Parakeet);
}

/// whisper-tiny should have Whisper backend with 1 file.
#[test]
fn registry_whisper_tiny_structure() {
    assert_eq!(MODELS[2].name, "whisper-tiny");
    assert_eq!(MODELS[2].backend, ModelBackend::Whisper);
    assert_eq!(MODELS[2].files.len(), 1);
}

/// All model names should be unique.
#[test]
fn model_names_are_unique() {
    let names: HashSet<&str> = MODELS.iter().map(|m| m.name).collect();
    assert_eq!(names.len(), MODELS.len());
}

/// All model file filenames within each model should be unique.
#[test]
fn model_filenames_unique_within_model() {
    for model in MODELS {
        let filenames: HashSet<&str> = model.files.iter().map(|f| f.filename).collect();
        assert_eq!(
            filenames.len(),
            model.files.len(),
            "Duplicate filenames in model '{}'",
            model.name
        );
    }
}

/// Parakeet models must have encoder-model.onnx, decoder_joint-model.onnx, and vocab.txt.
#[test]
fn parakeet_models_have_required_files() {
    for model in MODELS
        .iter()
        .filter(|m| m.backend == ModelBackend::Parakeet)
    {
        let filenames: Vec<&str> = model.files.iter().map(|f| f.filename).collect();
        assert!(
            filenames.contains(&"encoder-model.onnx"),
            "{} missing encoder-model.onnx",
            model.name
        );
        assert!(
            filenames.contains(&"decoder_joint-model.onnx"),
            "{} missing decoder_joint-model.onnx",
            model.name
        );
        assert!(
            filenames.contains(&"vocab.txt"),
            "{} missing vocab.txt",
            model.name
        );
    }
}

/// Whisper models must have a ggml-*.bin file.
#[test]
fn whisper_models_have_bin_file() {
    for model in MODELS.iter().filter(|m| m.backend == ModelBackend::Whisper) {
        let has_bin = model
            .files
            .iter()
            .any(|f| f.filename.starts_with("ggml-") && f.filename.ends_with(".bin"));
        assert!(has_bin, "{} missing ggml-*.bin file", model.name);
    }
}

// ---------------------------------------------------------------------------
// model_path
// ---------------------------------------------------------------------------

/// model_path for a known model should end with the model name.
#[test]
fn model_path_ends_with_model_name() {
    let path = model_path("parakeet-tdt-0.6b-v2").unwrap();
    assert!(path.to_string_lossy().ends_with("parakeet-tdt-0.6b-v2"));
}

/// model_path for a nonexistent model should return None.
#[test]
fn model_path_nonexistent_returns_none() {
    assert!(model_path("nonexistent").is_none());
}

// ---------------------------------------------------------------------------
// URLs
// ---------------------------------------------------------------------------

/// Every model file URL must use HTTPS.
#[test]
fn all_model_urls_are_https() {
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

// ---------------------------------------------------------------------------
// Sizes
// ---------------------------------------------------------------------------

/// Every model should have a positive size_mb.
#[test]
fn model_sizes_are_positive() {
    for model in MODELS {
        assert!(model.size_mb > 0, "Model {} has zero size", model.name);
    }
}

// ---------------------------------------------------------------------------
// SHA-256 hashes
// ---------------------------------------------------------------------------

/// Every non-empty SHA-256 hash should be exactly 64 lowercase hex characters.
#[test]
fn sha256_hashes_are_valid_hex() {
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

/// All registered models should have SHA-256 hashes for every file.
#[test]
fn all_models_have_sha256_hashes() {
    for model in MODELS {
        for file in model.files {
            assert!(
                !file.sha256.is_empty(),
                "Missing SHA-256 for {} in {}",
                file.filename,
                model.name
            );
        }
    }
}

// ---------------------------------------------------------------------------
// verify_file_sha256
// ---------------------------------------------------------------------------

/// verify_file_sha256 should return true for a file matching its expected hash.
#[test]
fn verify_sha256_correct_hash() {
    let tmp = std::env::temp_dir().join("dikto_sha256_test_correct");
    std::fs::write(&tmp, b"hello world").unwrap();

    // SHA-256 of "hello world"
    let expected = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9";
    assert!(verify_file_sha256(&tmp, expected));

    let _ = std::fs::remove_file(&tmp);
}

/// verify_file_sha256 should return false for a wrong hash.
#[test]
fn verify_sha256_wrong_hash() {
    let tmp = std::env::temp_dir().join("dikto_sha256_test_wrong");
    std::fs::write(&tmp, b"hello world").unwrap();

    let wrong = "0000000000000000000000000000000000000000000000000000000000000000";
    assert!(!verify_file_sha256(&tmp, wrong));

    let _ = std::fs::remove_file(&tmp);
}

/// verify_file_sha256 should return false for a nonexistent file.
#[test]
fn verify_sha256_nonexistent_file() {
    let path = std::path::Path::new("/tmp/dikto_sha256_nonexistent_file_xyz");
    assert!(!verify_file_sha256(path, "abc123"));
}

// ---------------------------------------------------------------------------
// is_model_downloaded
// ---------------------------------------------------------------------------

/// is_model_downloaded should return false for a model that hasn't been downloaded.
#[test]
fn is_model_downloaded_false_for_missing() {
    // Models are not downloaded in the test environment
    assert!(!is_model_downloaded("parakeet-tdt-0.6b-v2"));
}

/// is_model_downloaded should return false for a nonexistent model name.
#[test]
fn is_model_downloaded_false_for_nonexistent() {
    assert!(!is_model_downloaded("nonexistent-model-xyz"));
}

// ---------------------------------------------------------------------------
// list_models
// ---------------------------------------------------------------------------

/// list_models should return all 6 registered models.
#[test]
fn list_models_returns_all() {
    let models = list_models();
    assert_eq!(models.len(), 6);
}

/// list_models entries should have a consistent download status with is_model_downloaded.
#[test]
fn list_models_download_status_consistent() {
    let models = list_models();
    for (model, downloaded) in &models {
        // The download status from list_models should match is_model_downloaded
        assert_eq!(
            *downloaded,
            is_model_downloaded(model.name),
            "Inconsistent download status for model '{}'",
            model.name
        );
    }
}

// ---------------------------------------------------------------------------
// delete_model error paths
// ---------------------------------------------------------------------------

/// delete_model with an unknown name should return NotFound error.
#[test]
fn delete_model_unknown_returns_not_found() {
    let result = delete_model("nonexistent-model-xyz");
    assert!(result.is_err());
    let err = result.unwrap_err();
    assert!(err.to_string().contains("not found"));
}

// ---------------------------------------------------------------------------
// ModelError display
// ---------------------------------------------------------------------------

/// ModelError::NotFound should include the model name and available models.
#[test]
fn model_error_not_found_display() {
    let err = ModelError::NotFound("foo".to_string(), "a, b, c".to_string());
    let msg = err.to_string();
    assert!(msg.contains("foo"));
    assert!(msg.contains("a, b, c"));
}

/// ModelError::DownloadFailed should include the failure reason.
#[test]
fn model_error_download_failed_display() {
    let err = ModelError::DownloadFailed("timeout".to_string());
    assert!(err.to_string().contains("timeout"));
}
