mod setup;

use clap::Parser;

#[derive(Parser)]
#[command(name = "sotto", version, about = "Voice-to-text for macOS", arg_required_else_help = true)]
struct Cli {
    /// Download model and create default config
    #[arg(long)]
    setup: bool,

    /// Model to download (use with --setup). Default: parakeet-tdt-0.6b-v2
    #[arg(long)]
    model: Option<String>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    if cli.setup {
        setup::run_setup(cli.model.as_deref()).await?;
        return Ok(());
    }

    Ok(())
}
