#!/usr/bin/env node

import { execSync } from "node:child_process";
import { access, mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createWriteStream } from "node:fs";
import { pipeline } from "node:stream/promises";
import { DATA_DIR, CONFIG_DIR, DEFAULT_MODEL_PATH } from "./config.js";

const MODEL_URL =
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin";

function log(msg: string) {
  console.log(`  ${msg}`);
}

function logOk(msg: string) {
  console.log(`  [OK] ${msg}`);
}

function logFail(msg: string) {
  console.log(`  [!!] ${msg}`);
}

function checkCommand(cmd: string): boolean {
  try {
    execSync(`which ${cmd}`, { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

async function fileExists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function downloadModel(dest: string): Promise<void> {
  const dir = join(dest, "..");
  await mkdir(dir, { recursive: true });

  log(`Downloading whisper base.en model (~150MB)...`);
  log(`From: ${MODEL_URL}`);
  log(`To:   ${dest}`);
  log(``);

  const response = await fetch(MODEL_URL);
  if (!response.ok || !response.body) {
    throw new Error(`Download failed: HTTP ${response.status}`);
  }

  const totalBytes = Number(response.headers.get("content-length") || 0);
  let downloadedBytes = 0;

  const fileStream = createWriteStream(dest);

  const reader = response.body.getReader();

  const writable = new WritableStream({
    write(chunk: Uint8Array) {
      downloadedBytes += chunk.length;
      fileStream.write(chunk);
      if (totalBytes > 0) {
        const pct = ((downloadedBytes / totalBytes) * 100).toFixed(1);
        process.stdout.write(`\r  Downloading... ${pct}%`);
      }
    },
    close() {
      fileStream.end();
      console.log(); // newline after progress
    },
  });

  // Pipe reader to writable
  const readable = new ReadableStream({
    async start(controller) {
      while (true) {
        const { done, value } = await reader.read();
        if (done) {
          controller.close();
          break;
        }
        controller.enqueue(value);
      }
    },
  });

  await readable.pipeTo(writable);

  // Wait for file stream to finish
  await new Promise<void>((resolve, reject) => {
    fileStream.on("finish", resolve);
    fileStream.on("error", reject);
  });
}

async function main() {
  console.log();
  console.log("sotto setup");
  console.log("===========");
  console.log();

  // Check Node.js version
  const nodeVersion = process.versions.node;
  const major = parseInt(nodeVersion.split(".")[0], 10);
  if (major >= 18) {
    logOk(`Node.js ${nodeVersion}`);
  } else {
    logFail(`Node.js ${nodeVersion} — version 18+ required`);
    process.exit(1);
  }

  // Check speech-recorder
  try {
    await import("speech-recorder");
    logOk("speech-recorder (native addon loaded)");
  } catch {
    logFail("speech-recorder native addon failed to load — try: npm rebuild speech-recorder");
    process.exit(1);
  }

  // Check whisper-cpp (binary is whisper-cli)
  if (checkCommand("whisper-cli")) {
    logOk("whisper-cpp (whisper-cli found)");
  } else {
    logFail("whisper-cpp not found — install with: brew install whisper-cpp");
    process.exit(1);
  }

  // Check/download model
  console.log();
  if (await fileExists(DEFAULT_MODEL_PATH)) {
    logOk(`Model found at ${DEFAULT_MODEL_PATH}`);
  } else {
    log("Model not found. Downloading...");
    console.log();
    try {
      await downloadModel(DEFAULT_MODEL_PATH);
      logOk(`Model downloaded to ${DEFAULT_MODEL_PATH}`);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logFail(`Failed to download model: ${msg}`);
      process.exit(1);
    }
  }

  // Create config directory
  await mkdir(CONFIG_DIR, { recursive: true });

  // Create default config if it doesn't exist
  const configPath = join(CONFIG_DIR, "config.json");
  if (!(await fileExists(configPath))) {
    await writeFile(
      configPath,
      JSON.stringify(
        {
          modelPath: DEFAULT_MODEL_PATH,
          language: "en",
          maxDuration: 30,
          consecutiveFramesForSilence: 200,
          sileroVadSpeakingThreshold: 0.5,
        },
        null,
        2
      ) + "\n"
    );
    logOk(`Config created at ${configPath}`);
  } else {
    logOk(`Config exists at ${configPath}`);
  }

  console.log();
  console.log("Setup complete! Next steps:");
  console.log();
  console.log("  1. Register with Claude Code:");
  console.log("     claude mcp add sotto -- sotto");
  console.log();
  console.log("  2. In Claude Code, use the /mcp__sotto__listen command");
  console.log("     to speak instead of typing.");
  console.log();
}

main().catch((error) => {
  console.error("Setup failed:", error);
  process.exit(1);
});
