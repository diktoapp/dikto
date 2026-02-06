export interface WhisperConfig {
  modelPath: string;
  language: string;
  maxDuration: number;
  consecutiveFramesForSilence: number;
  sileroVadSpeakingThreshold: number;
}

export interface RecordingOptions {
  maxDuration: number;
  consecutiveFramesForSilence: number;
  sileroVadSpeakingThreshold: number;
}

export interface RecordingResult {
  filePath: string;
  durationMs: number;
}

export interface TranscriptionOptions {
  modelPath: string;
  language: string;
}

export interface TranscriptionResult {
  text: string;
}
