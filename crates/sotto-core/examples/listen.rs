//! CLI example that captures mic, runs VAD + Parakeet TDT, and prints transcript.
//! Usage: cargo run --example listen

use sotto_core::{
    ListenConfig, RecordingState, SottoEngine, TranscriptionCallback,
};
use std::sync::{Arc, Condvar, Mutex};

struct CompletionSignal {
    result: Mutex<Option<Result<String, String>>>,
    condvar: Condvar,
}

struct PrintCallback {
    completion: Arc<CompletionSignal>,
}

impl TranscriptionCallback for PrintCallback {
    fn on_partial(&self, text: String) {
        eprint!("\r\x1b[K[partial] {text}");
    }

    fn on_final_segment(&self, text: String) {
        eprintln!("\r\x1b[K[final] {text}");
    }

    fn on_silence(&self) {
        eprintln!("\r\x1b[K[silence detected]");
    }

    fn on_error(&self, error: String) {
        eprintln!("\r\x1b[K[error] {error}");
    }

    fn on_state_change(&self, state: RecordingState) {
        match state {
            RecordingState::Listening => eprintln!("[state] Listening..."),
            RecordingState::Processing => eprintln!("[state] Processing..."),
            RecordingState::Done { ref text } => {
                eprintln!("[state] Done!");
                println!("{text}");
                let mut result = self.completion.result.lock().unwrap();
                *result = Some(Ok(text.clone()));
                self.completion.condvar.notify_all();
            }
            RecordingState::Error { ref message } => {
                eprintln!("[state] Error: {message}");
                let mut result = self.completion.result.lock().unwrap();
                *result = Some(Err(message.clone()));
                self.completion.condvar.notify_all();
            }
        }
    }
}

fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("sotto_core=debug".parse().unwrap()),
        )
        .init();

    let engine = SottoEngine::new();

    eprintln!("Loading model...");
    engine.load_model()?;
    eprintln!("Model loaded! Speak into your microphone (max 30s, or silence to stop).");

    let config = ListenConfig::default();

    let completion = Arc::new(CompletionSignal {
        result: Mutex::new(None),
        condvar: Condvar::new(),
    });

    let callback = Arc::new(PrintCallback {
        completion: completion.clone(),
    });

    let _handle = engine.start_listening(config, callback)?;

    // Wait for completion
    let mut guard = completion.result.lock().unwrap();
    while guard.is_none() {
        guard = completion.condvar.wait(guard).unwrap();
    }

    let result = guard.take().unwrap();
    match result {
        Ok(text) => eprintln!("\nFinal transcript: {text}"),
        Err(e) => eprintln!("\nError: {e}"),
    }

    Ok(())
}
