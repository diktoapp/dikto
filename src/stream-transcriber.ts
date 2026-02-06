import { spawn, type ChildProcess } from "node:child_process";
import { access } from "node:fs/promises";
import type { StreamTranscriptionOptions, StreamCallbacks } from "./types.js";

const ANSI_RE = /\x1b\[[0-9;]*[a-zA-Z]/g;
const BLANK_AUDIO_RE = /\[BLANK_AUDIO\]/;
const START_SPEAKING_RE = /\[Start speaking\]/;

export function stripAnsi(str: string): string {
  return str.replace(ANSI_RE, "");
}

export function isFilteredLine(text: string): boolean {
  const trimmed = text.trim();
  return (
    trimmed.length === 0 ||
    BLANK_AUDIO_RE.test(trimmed) ||
    START_SPEAKING_RE.test(trimmed)
  );
}

export function isBlankAudio(text: string): boolean {
  return BLANK_AUDIO_RE.test(text);
}

export function parseStreamChunk(raw: string): { segments: Array<{ text: string; isFinal: boolean; isBlank: boolean }> } {
  const cleaned = stripAnsi(raw);
  const segments: Array<{ text: string; isFinal: boolean; isBlank: boolean }> = [];

  // Split on \n first to get finalized lines, then check for \r within them
  // whisper-stream uses \r for partial overwrites and \n for finalized lines
  const parts = cleaned.split("\n");

  for (const part of parts) {
    // Each part may contain \r-separated partial updates; take the last one
    const subparts = part.split("\r");
    const lastPart = subparts[subparts.length - 1];
    const trimmed = lastPart.trim();

    if (trimmed.length === 0) continue;

    const blank = isBlankAudio(trimmed);
    const filtered = isFilteredLine(trimmed);

    if (filtered && !blank) continue;

    segments.push({
      text: trimmed,
      isFinal: true, // lines separated by \n are finalized
      isBlank: blank,
    });
  }

  return { segments };
}

export interface StreamTranscribeHandle {
  promise: Promise<string>;
  stop: () => void;
}

export async function streamTranscribe(
  options: StreamTranscriptionOptions,
  callbacks: StreamCallbacks = {}
): Promise<StreamTranscribeHandle> {
  // Check that whisper-stream is available
  await checkWhisperStream();
  await checkModel(options.modelPath);

  const step = options.step ?? 3000;
  const length = options.length ?? 5000;
  const keep = options.keep ?? 200;
  const silenceBlankCount = options.silenceBlankCount ?? 3;

  const args = [
    "-m", options.modelPath,
    "-l", options.language,
    "--step", String(step),
    "--length", String(length),
    "--keep", String(keep),
    "-kc",
  ];

  let externalStop: () => void;

  const promise = new Promise<string>((resolve, reject) => {
    let proc: ChildProcess;
    try {
      proc = spawn("whisper-stream", args, {
        stdio: ["ignore", "pipe", "pipe"],
      });
    } catch (err) {
      reject(new Error(`Failed to spawn whisper-stream: ${err instanceof Error ? err.message : String(err)}`));
      return;
    }

    const finalLines: string[] = [];
    let consecutiveBlanks = 0;
    let stopped = false;
    let buffer = "";

    function stop() {
      if (stopped) return;
      stopped = true;
      try {
        proc.kill("SIGTERM");
      } catch {
        // process may have already exited
      }
    }

    externalStop = stop;

    // maxDuration timeout
    const timeout = setTimeout(() => {
      stop();
    }, options.maxDuration * 1000);

    proc.stdout?.on("data", (data: Buffer) => {
      if (stopped) return;

      buffer += data.toString();

      // Process complete lines (ending with \n)
      const nlIndex = buffer.lastIndexOf("\n");
      if (nlIndex === -1) {
        // No complete line yet — check for partial (\r)
        const crIndex = buffer.lastIndexOf("\r");
        if (crIndex !== -1) {
          const partial = stripAnsi(buffer.substring(0, crIndex));
          const subparts = partial.split("\r");
          const lastPartial = subparts[subparts.length - 1].trim();
          if (lastPartial && !isFilteredLine(lastPartial)) {
            callbacks.onPartial?.(lastPartial);
          }
          // Keep the part after the last \r as the new buffer
          buffer = buffer.substring(crIndex + 1);
        }
        return;
      }

      const complete = buffer.substring(0, nlIndex + 1);
      buffer = buffer.substring(nlIndex + 1);

      const { segments } = parseStreamChunk(complete);

      for (const seg of segments) {
        if (seg.isBlank) {
          consecutiveBlanks++;
          if (consecutiveBlanks >= silenceBlankCount) {
            callbacks.onSilence?.();
            stop();
            return;
          }
          continue;
        }

        consecutiveBlanks = 0;

        if (seg.isFinal) {
          finalLines.push(seg.text);
          callbacks.onFinal?.(seg.text);
        } else {
          callbacks.onPartial?.(seg.text);
        }
      }
    });

    let stderr = "";
    proc.stderr?.on("data", (data: Buffer) => {
      stderr += data.toString();
    });

    proc.on("error", (err) => {
      clearTimeout(timeout);
      if (!stopped) {
        reject(new Error(`whisper-stream error: ${err.message}`));
      }
    });

    proc.on("close", (code) => {
      clearTimeout(timeout);

      // Flush any remaining buffer content (last words before SIGTERM)
      if (buffer.length > 0) {
        const { segments } = parseStreamChunk(buffer + "\n");
        for (const seg of segments) {
          if (!seg.isBlank) {
            finalLines.push(seg.text);
            callbacks.onFinal?.(seg.text);
          }
        }
        buffer = "";
      }

      const text = finalLines.join(" ").trim() || "[No speech detected]";
      // SIGTERM exit (null or 143) is expected
      if (code !== 0 && code !== null && code !== 143 && !stopped) {
        reject(new Error(`whisper-stream exited with code ${code}: ${stderr.trim()}`));
        return;
      }
      resolve(text);
    });
  });

  return { promise, stop: externalStop! };
}

function checkWhisperStream(): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc = spawn("which", ["whisper-stream"]);
    proc.on("close", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(
          new Error(
            "whisper-stream is not installed. Install it with: brew install whisper-cpp"
          )
        );
      }
    });
    proc.on("error", () => {
      reject(
        new Error(
          "whisper-stream is not installed. Install it with: brew install whisper-cpp"
        )
      );
    });
  });
}

async function checkModel(modelPath: string): Promise<void> {
  try {
    await access(modelPath);
  } catch {
    throw new Error(
      `Whisper model not found at ${modelPath}. Run: sotto-setup`
    );
  }
}
