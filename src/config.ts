import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";
import type { WhisperConfig } from "./types.js";

const CONFIG_DIR = join(homedir(), ".config", "sotto");
const CONFIG_FILE = join(CONFIG_DIR, "config.json");
const DATA_DIR = join(homedir(), ".local", "share", "sotto");
const DEFAULT_MODEL_PATH = join(DATA_DIR, "models", "ggml-base.en.bin");

const DEFAULTS: WhisperConfig = {
  modelPath: DEFAULT_MODEL_PATH,
  language: "en",
  maxDuration: 30,
  consecutiveFramesForSilence: 200,
  sileroVadSpeakingThreshold: 0.5,
};

async function loadConfigFile(): Promise<Partial<WhisperConfig>> {
  try {
    const raw = await readFile(CONFIG_FILE, "utf-8");
    return JSON.parse(raw) as Partial<WhisperConfig>;
  } catch {
    return {};
  }
}

function loadEnvVars(): Partial<WhisperConfig> {
  const config: Partial<WhisperConfig> = {};
  if (process.env.WHISPER_MODEL_PATH) {
    config.modelPath = process.env.WHISPER_MODEL_PATH;
  }
  if (process.env.WHISPER_LANGUAGE) {
    config.language = process.env.WHISPER_LANGUAGE;
  }
  if (process.env.WHISPER_MAX_DURATION) {
    const parsed = parseInt(process.env.WHISPER_MAX_DURATION, 10);
    if (!isNaN(parsed) && parsed > 0) {
      config.maxDuration = parsed;
    }
  }
  return config;
}

export async function loadConfig(): Promise<WhisperConfig> {
  const fileConfig = await loadConfigFile();
  const envConfig = loadEnvVars();

  // Precedence: env vars > config file > defaults
  return {
    ...DEFAULTS,
    ...fileConfig,
    ...envConfig,
  };
}

export { CONFIG_DIR, CONFIG_FILE, DATA_DIR, DEFAULT_MODEL_PATH, DEFAULTS };
