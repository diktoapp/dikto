declare module "speech-recorder" {
  export interface OnChunkStartData {
    audio: Int16Array;
  }

  export interface OnAudioData {
    audio: Int16Array;
    speaking: boolean;
    probability: number;
    volume: number;
    speech: boolean;
    consecutiveSilence: number;
  }

  export interface SpeechRecorderOptions {
    consecutiveFramesForSilence?: number;
    consecutiveFramesForSpeaking?: number;
    device?: number;
    leadingBufferFrames?: number;
    samplesPerFrame?: number;
    sampleRate?: number;
    sileroVadBufferSize?: number;
    sileroVadRateLimit?: number;
    sileroVadSilenceThreshold?: number;
    sileroVadSpeakingThreshold?: number;
    webrtcVadLevel?: number;
    webrtcVadBufferSize?: number;
    webrtcVadResultsSize?: number;
    onChunkStart?: (data: OnChunkStartData) => void;
    onAudio?: (data: OnAudioData) => void;
    onChunkEnd?: () => void;
  }

  export interface Device {
    id: number;
    name: string;
    apiName: string;
    maxInputChannels: number;
    maxOutputChannels: number;
    defaultSampleRate: number;
    isDefaultInput: boolean;
    isDefaultOutput: boolean;
  }

  export class SpeechRecorder {
    constructor(options?: SpeechRecorderOptions);
    start(): void;
    stop(): void;
    processFile(filePath: string): void;
  }

  export function devices(): Device[];
}
