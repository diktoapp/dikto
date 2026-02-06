import { describe, it, expect, vi, beforeEach } from "vitest";
import type { SpeechRecorderOptions } from "speech-recorder";

let mockStart: ReturnType<typeof vi.fn>;
let mockStop: ReturnType<typeof vi.fn>;
let capturedOptions: SpeechRecorderOptions;

vi.mock("speech-recorder", () => {
  return {
    SpeechRecorder: vi.fn().mockImplementation((options: SpeechRecorderOptions) => {
      capturedOptions = options;
      mockStart = vi.fn(() => {
        // Simulate speech: onChunkStart → onAudio frames → onChunkEnd
        if (options.onChunkStart) {
          options.onChunkStart({ audio: new Int16Array([1, 2, 3]) });
        }
        if (options.onAudio) {
          options.onAudio({
            audio: new Int16Array([4, 5, 6]),
            speaking: true,
            probability: 0.9,
            volume: 0.5,
            speech: true,
            consecutiveSilence: 0,
          });
        }
        if (options.onChunkEnd) {
          options.onChunkEnd();
        }
      });
      mockStop = vi.fn();
      return { start: mockStart, stop: mockStop };
    }),
  };
});

vi.mock("node:fs/promises", async () => {
  const actual = await vi.importActual<typeof import("node:fs/promises")>("node:fs/promises");
  return {
    ...actual,
    mkdtemp: vi.fn().mockResolvedValue("/tmp/sotto-test"),
    writeFile: vi.fn().mockResolvedValue(undefined),
    rm: vi.fn().mockResolvedValue(undefined),
  };
});

import { checkSpeechRecorder, record, cleanupRecording } from "../src/recorder.js";
import { writeFile } from "node:fs/promises";

beforeEach(() => {
  vi.clearAllMocks();
});

describe("recorder", () => {
  describe("checkSpeechRecorder", () => {
    it("should resolve when speech-recorder native addon loads", async () => {
      await expect(checkSpeechRecorder()).resolves.toBeUndefined();
    });
  });

  describe("record", () => {
    it("should create SpeechRecorder with correct options", async () => {
      const { SpeechRecorder } = await import("speech-recorder");

      await record({
        maxDuration: 30,
        consecutiveFramesForSilence: 200,
        sileroVadSpeakingThreshold: 0.5,
      });

      expect(SpeechRecorder).toHaveBeenCalledWith(
        expect.objectContaining({
          sampleRate: 16000,
          consecutiveFramesForSilence: 200,
          sileroVadSpeakingThreshold: 0.5,
        })
      );
    });

    it("should collect audio from onChunkStart and onAudio, then write WAV on onChunkEnd", async () => {
      const result = await record({
        maxDuration: 30,
        consecutiveFramesForSilence: 200,
        sileroVadSpeakingThreshold: 0.5,
      });

      expect(result.filePath).toBe("/tmp/sotto-test/recording.wav");
      expect(result.durationMs).toBeGreaterThanOrEqual(0);

      // WAV file should have been written
      expect(writeFile).toHaveBeenCalledWith(
        "/tmp/sotto-test/recording.wav",
        expect.any(Buffer)
      );

      // Verify WAV header
      const wavBuffer = vi.mocked(writeFile).mock.calls[0][1] as Buffer;
      expect(wavBuffer.toString("ascii", 0, 4)).toBe("RIFF");
      expect(wavBuffer.toString("ascii", 8, 12)).toBe("WAVE");
      expect(wavBuffer.toString("ascii", 12, 16)).toBe("fmt ");
      expect(wavBuffer.readUInt16LE(20)).toBe(1); // PCM format
      expect(wavBuffer.readUInt16LE(22)).toBe(1); // mono
      expect(wavBuffer.readUInt32LE(24)).toBe(16000); // sample rate
      expect(wavBuffer.readUInt16LE(34)).toBe(16); // bits per sample
    });

    it("should handle maxDuration hard cap", async () => {
      // Override mock to never call onChunkEnd (simulate ongoing speech)
      const { SpeechRecorder } = await import("speech-recorder");
      vi.mocked(SpeechRecorder).mockImplementationOnce((options: SpeechRecorderOptions) => {
        capturedOptions = options;
        mockStart = vi.fn(() => {
          // Speech starts but never ends
          if (options.onChunkStart) {
            options.onChunkStart({ audio: new Int16Array([1, 2, 3]) });
          }
          if (options.onAudio) {
            options.onAudio({
              audio: new Int16Array([4, 5, 6]),
              speaking: true,
              probability: 0.9,
              volume: 0.5,
              speech: true,
              consecutiveSilence: 0,
            });
          }
          // No onChunkEnd — timeout should fire
        });
        mockStop = vi.fn();
        return { start: mockStart, stop: mockStop } as any;
      });

      vi.useFakeTimers();

      const promise = record({
        maxDuration: 5,
        consecutiveFramesForSilence: 200,
        sileroVadSpeakingThreshold: 0.5,
      });

      // Advance past the maxDuration timeout
      await vi.advanceTimersByTimeAsync(5000);

      const result = await promise;
      expect(result.filePath).toBe("/tmp/sotto-test/recording.wav");
      expect(mockStop).toHaveBeenCalled();

      vi.useRealTimers();
    });

    it("should handle empty recording (no speech) gracefully", async () => {
      const { SpeechRecorder } = await import("speech-recorder");
      vi.mocked(SpeechRecorder).mockImplementationOnce((options: SpeechRecorderOptions) => {
        capturedOptions = options;
        mockStart = vi.fn(() => {
          // No speech at all — just silence, then onChunkEnd never fires
        });
        mockStop = vi.fn();
        return { start: mockStart, stop: mockStop } as any;
      });

      vi.useFakeTimers();

      const promise = record({
        maxDuration: 5,
        consecutiveFramesForSilence: 200,
        sileroVadSpeakingThreshold: 0.5,
      });

      await vi.advanceTimersByTimeAsync(5000);

      const result = await promise;
      expect(result.filePath).toBe("/tmp/sotto-test/recording.wav");

      // Should write a WAV even with no speech (silent fallback)
      expect(writeFile).toHaveBeenCalled();

      vi.useRealTimers();
    });

    it("should reject if recorder.start() throws", async () => {
      const { SpeechRecorder } = await import("speech-recorder");
      // First call: checkSpeechRecorder() — let it succeed
      vi.mocked(SpeechRecorder).mockImplementationOnce(() => {
        return { start: vi.fn(), stop: vi.fn() } as any;
      });
      // Second call: actual recording — throw on start
      vi.mocked(SpeechRecorder).mockImplementationOnce((options: SpeechRecorderOptions) => {
        capturedOptions = options;
        mockStart = vi.fn(() => {
          throw new Error("Microphone not available");
        });
        mockStop = vi.fn();
        return { start: mockStart, stop: mockStop } as any;
      });

      await expect(
        record({
          maxDuration: 30,
          consecutiveFramesForSilence: 200,
          sileroVadSpeakingThreshold: 0.5,
        })
      ).rejects.toThrow("Failed to start recording: Microphone not available");
    });
  });

  describe("cleanupRecording", () => {
    it("should not throw on cleanup", async () => {
      await expect(cleanupRecording("/tmp/sotto-test/recording.wav")).resolves.toBeUndefined();
    });
  });
});
