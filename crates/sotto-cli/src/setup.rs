use sotto_core::config::{self, SottoConfig};
use sotto_core::models;

/// Run the setup command: download a model and create config.
/// If `model_name` is None, downloads the default model (parakeet-tdt-0.6b-v2).
pub async fn run_setup(model_name: Option<&str>) -> anyhow::Result<()> {
    eprintln!("Sotto Setup");
    eprintln!("===========\n");

    // Ensure directories exist
    let config_dir = config::config_dir();
    let models_dir = config::models_dir();
    std::fs::create_dir_all(&config_dir)?;
    std::fs::create_dir_all(&models_dir)?;

    // Create default config if it doesn't exist
    let config_path = config::config_path();
    if !config_path.exists() {
        let cfg = SottoConfig::default();
        config::save_config(&cfg)?;
        eprintln!("Created config at {}", config_path.display());
    } else {
        eprintln!("Config already exists at {}", config_path.display());
    }

    // Resolve model name
    let model_name = model_name.unwrap_or("parakeet-tdt-0.6b-v2");

    // Validate model name
    let model = match models::find_model(model_name) {
        Some(m) => m,
        None => {
            eprintln!("Unknown model: '{model_name}'\n");
            eprintln!("Available models:");
            for (m, downloaded) in models::list_models() {
                let status = if downloaded { "downloaded" } else { "not downloaded" };
                eprintln!(
                    "  {:<30} {:>8} MB  ({})  [{}]",
                    m.name,
                    m.size_mb,
                    m.description,
                    status
                );
            }
            anyhow::bail!("Invalid model name: {model_name}");
        }
    };

    // Download model if not present
    if models::is_model_downloaded(model_name) {
        eprintln!("Model '{model_name}' already downloaded.");
    } else {
        eprintln!(
            "Downloading model '{model_name}' (~{} MB, {} file{})...",
            model.size_mb,
            model.files.len(),
            if model.files.len() == 1 { "" } else { "s" }
        );

        let total_bytes: u64 = model.files.iter().map(|f| f.size_mb as u64 * 1024 * 1024).sum();
        let bar = indicatif::ProgressBar::new(total_bytes);
        bar.set_style(
            indicatif::ProgressStyle::default_bar()
                .template("[{elapsed_precise}] [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({eta})")
                .unwrap()
                .progress_chars("=> "),
        );

        let bar_clone = bar.clone();
        let path = models::download_model(model_name, move |downloaded, total| {
            if total > 0 {
                bar_clone.set_length(total);
            }
            bar_clone.set_position(downloaded);
        })
        .await?;

        bar.finish_with_message("Download complete!");
        eprintln!("Model saved to {}", path.display());
    }

    eprintln!("\nSetup complete! You can now use sotto.");
    eprintln!("  Desktop app: open /Applications/Sotto.app");

    Ok(())
}
