mod mcp;
mod setup;

use clap::Parser;

#[derive(Parser)]
#[command(name = "sotto", version, about = "Voice-to-text for macOS")]
struct Cli {
    /// Run as MCP server (for Claude Code integration)
    #[arg(long)]
    mcp: bool,

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

    if cli.mcp {
        // MCP mode: no subscriber on stderr (it would interfere with stdio transport)
        mcp::run_mcp_server().await?;
        return Ok(());
    }

    // Default: for now, print help. Phase 3 will launch SwiftUI app.
    eprintln!("Sotto v{}", env!("CARGO_PKG_VERSION"));
    eprintln!();
    eprintln!("Usage:");
    eprintln!("  sotto --mcp     Run as MCP server (for Claude Code)");
    eprintln!("  sotto --setup   Download model and create config");
    eprintln!();
    eprintln!("Desktop app coming in Phase 3.");

    Ok(())
}
