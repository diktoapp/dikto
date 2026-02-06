import { SpeechRecorder } from "speech-recorder";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import type { RecordingOptions, RecordingResult } from "./types.js";

const SAMPLE_RATE = 16000;
const BITS_PER_SAMPLE = 16;
const NUM_CHANNELS = 1;

function buildWav(chunks: Int16Array[]): Buffer {
  let totalSamples = 0;
  for (const chunk of chunks) {
    totalSamples += chunk.length;
  }

  const dataBytes = totalSamples * (BITS_PER_SAMPLE / 8);
  const buffer = Buffer.alloc(44 + dataBytes);

  // RIFF header
  buffer.write("RIFF", 0);
  buffer.writeUInt32LE(36 + dataBytes, 4);
  buffer.write("WAVE", 8);

  // fmt chunk
  buffer.write("fmt ", 12);
  buffer.writeUInt32LE(16, 16); // chunk size
  buffer.writeUInt16LE(1, 20); // PCM format
  buffer.writeUInt16LE(NUM_CHANNELS, 22);
  buffer.writeUInt32LE(SAMPLE_RATE, 24);
  buffer.writeUInt32LE(SAMPLE_RATE * NUM_CHANNELS * (BITS_PER_SAMPLE / 8), 28); // byte rate
  buffer.writeUInt16LE(NUM_CHANNELS * (BITS_PER_SAMPLE / 8), 32); // block align
  buffer.writeUInt16LE(BITS_PER_SAMPLE, 34);

  // data chunk
  buffer.write("data", 36);
  buffer.writeUInt32LE(dataBytes, 40);

  let offset = 44;
  for (const chunk of chunks) {
    for (let i = 0; i < chunk.length; i++) {
      buffer.writeInt16LE(chunk[i], offset);
      offset += 2;
    }
  }

  return buffer;
}

export function checkSpeechRecorder(): void {
  // Verify the native addon loaded successfully via the static import.
  // We avoid creating a temporary SpeechRecorder instance because
  // constructing and stopping one prevents subsequent instances from
  // working (native addon segfault).
  if (typeof SpeechRecorder !== "function") {
    throw new Error(
      "speech-recorder native addon failed to load. Try reinstalling: npm rebuild speech-recorder"
    );
  }
}

export async function record(options: RecordingOptions): Promise<RecordingResult> {
  checkSpeechRecorder();

  const tempDir = await mkdtemp(join(tmpdir(), "sotto-"));
  const filePath = join(tempDir, "recording.wav");

  const startTime = Date.now();

  return new Promise<RecordingResult>((resolve, reject) => {
    const audioChunks: Int16Array[] = [];
    let speaking = false;
    let resolved = false;

    function finish() {
      if (resolved) return;
      resolved = true;
      clearTimeout(timeout);
      recorder.stop();

      const durationMs = Date.now() - startTime;

      if (audioChunks.length === 0) {
        // No speech detected — write a minimal silent WAV so downstream doesn't crash
        const silence = new Int16Array(SAMPLE_RATE); // 1s of silence
        audioChunks.push(silence);
      }

      const wav = buildWav(audioChunks);
      writeFile(filePath, wav)
        .then(() => resolve({ filePath, durationMs }))
        .catch(reject);
    }

    const recorder = new SpeechRecorder({
      sampleRate: SAMPLE_RATE,
      consecutiveFramesForSilence: options.consecutiveFramesForSilence,
      sileroVadSpeakingThreshold: options.sileroVadSpeakingThreshold,

      onChunkStart({ audio }) {
        speaking = true;
        // Include pre-speech buffer
        audioChunks.push(new Int16Array(audio));
      },

      onAudio({ audio, speaking: isSpeaking }) {
        if (speaking && isSpeaking) {
          audioChunks.push(new Int16Array(audio));
        }
      },

      onChunkEnd() {
        // Speech ended — finalize the recording
        finish();
      },
    });

    const timeout = setTimeout(() => {
      finish();
    }, options.maxDuration * 1000);

    try {
      recorder.start();
    } catch (err) {
      resolved = true;
      clearTimeout(timeout);
      reject(
        new Error(
          `Failed to start recording: ${err instanceof Error ? err.message : String(err)}`
        )
      );
    }
  });
}

export async function cleanupRecording(filePath: string): Promise<void> {
  try {
    // Remove the temp directory containing the recording
    const dir = join(filePath, "..");
    await rm(dir, { recursive: true, force: true });
  } catch {
    // Ignore cleanup errors
  }
}
