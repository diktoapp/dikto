import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ChildProcess } from "node:child_process";
import { EventEmitter } from "node:events";

// Mock child_process
const mockKill = vi.fn();
let spawnCalls: Array<{ cmd: string; args: string[] }> = [];
let mockProc: EventEmitter & {
  stdout: EventEmitter;
  stderr: EventEmitter;
  stdin: null;
  kill: typeof mockKill;
  exitCode: number | null;
};

function createMockProc() {
  const proc = new EventEmitter() as any;
  proc.stdout = new EventEmitter();
  proc.stderr = new EventEmitter();
  proc.stdin = null;
  proc.kill = mockKill;
  proc.exitCode = null;
  return proc;
}

vi.mock("node:child_process", () => ({
  spawn: vi.fn((...args: any[]) => {
    const [cmd, cmdArgs] = args;
    spawnCalls.push({ cmd, args: cmdArgs });
    // For "which" command, immediately resolve
    if (cmd === "which") {
      const proc = createMockProc();
      setTimeout(() => proc.emit("close", 0), 0);
      return proc;
    }
    // For whisper-stream, return a controllable mock
    mockProc = createMockProc();
    return mockProc;
  }),
}));

vi.mock("node:fs/promises", () => ({
  access: vi.fn().mockResolvedValue(undefined),
}));

// Import pure functions directly — they don't need mocks
const { stripAnsi, isFilteredLine, isBlankAudio, parseStreamChunk, streamTranscribe } =
  await import("../src/stream-transcriber.js");

describe("stream-transcriber", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    spawnCalls = [];
  });

  describe("stripAnsi", () => {
    it("should remove ANSI escape codes", () => {
      expect(stripAnsi("\x1b[2KHello world")).toBe("Hello world");
      expect(stripAnsi("\x1b[0mtest\x1b[1m")).toBe("test");
      expect(stripAnsi("\x1b[32;1mcolored\x1b[0m")).toBe("colored");
    });

    it("should pass through clean text unchanged", () => {
      expect(stripAnsi("Hello world")).toBe("Hello world");
    });

    it("should handle empty string", () => {
      expect(stripAnsi("")).toBe("");
    });
  });

  describe("isFilteredLine", () => {
    it("should filter empty strings", () => {
      expect(isFilteredLine("")).toBe(true);
      expect(isFilteredLine("   ")).toBe(true);
    });

    it("should filter [BLANK_AUDIO]", () => {
      expect(isFilteredLine("[BLANK_AUDIO]")).toBe(true);
    });

    it("should filter [Start speaking]", () => {
      expect(isFilteredLine("[Start speaking]")).toBe(true);
    });

    it("should not filter normal text", () => {
      expect(isFilteredLine("Hello world")).toBe(false);
    });
  });

  describe("isBlankAudio", () => {
    it("should detect [BLANK_AUDIO]", () => {
      expect(isBlankAudio("[BLANK_AUDIO]")).toBe(true);
      expect(isBlankAudio("  [BLANK_AUDIO]  ")).toBe(true);
    });

    it("should not match normal text", () => {
      expect(isBlankAudio("Hello")).toBe(false);
    });
  });

  describe("parseStreamChunk", () => {
    it("should parse a simple finalized line", () => {
      const result = parseStreamChunk("Hello world\n");
      expect(result.segments).toHaveLength(1);
      expect(result.segments[0]).toEqual({
        text: "Hello world",
        isFinal: true,
        isBlank: false,
      });
    });

    it("should strip ANSI codes from output", () => {
      const result = parseStreamChunk("\x1b[2KHello world\n");
      expect(result.segments).toHaveLength(1);
      expect(result.segments[0].text).toBe("Hello world");
    });

    it("should handle \\r-separated partial updates within a line", () => {
      const result = parseStreamChunk("Hel\rHello\rHello world\n");
      expect(result.segments).toHaveLength(1);
      expect(result.segments[0].text).toBe("Hello world");
    });

    it("should mark [BLANK_AUDIO] lines as blank", () => {
      const result = parseStreamChunk("[BLANK_AUDIO]\n");
      expect(result.segments).toHaveLength(1);
      expect(result.segments[0].isBlank).toBe(true);
    });

    it("should filter out [Start speaking] lines", () => {
      const result = parseStreamChunk("[Start speaking]\n");
      expect(result.segments).toHaveLength(0);
    });

    it("should parse multiple lines", () => {
      const result = parseStreamChunk("Hello\nWorld\n");
      expect(result.segments).toHaveLength(2);
      expect(result.segments[0].text).toBe("Hello");
      expect(result.segments[1].text).toBe("World");
    });

    it("should skip empty lines", () => {
      const result = parseStreamChunk("\n\nHello\n\n");
      expect(result.segments).toHaveLength(1);
      expect(result.segments[0].text).toBe("Hello");
    });
  });

  describe("streamTranscribe", () => {
    it("should spawn whisper-stream with correct args", async () => {
      const handlePromise = streamTranscribe(
        {
          modelPath: "/path/to/model.bin",
          language: "en",
          maxDuration: 30,
        },
        {}
      );

      // Let the "which" check resolve
      await vi.waitFor(() => {
        expect(spawnCalls.some((c) => c.cmd === "whisper-stream")).toBe(true);
      });

      const wsCall = spawnCalls.find((c) => c.cmd === "whisper-stream");
      expect(wsCall!.args).toEqual([
        "-m", "/path/to/model.bin",
        "-l", "en",
        "--step", "3000",
        "--length", "5000",
        "--keep", "200",
        "-kc",
      ]);

      // End the process cleanly
      const { promise } = await handlePromise;
      mockProc.emit("close", 0);
      const result = await promise;
      expect(result).toBe("[No speech detected]");
    });

    it("should accumulate final lines and return them", async () => {
      const handle = await streamTranscribe(
        {
          modelPath: "/path/to/model.bin",
          language: "en",
          maxDuration: 30,
        },
        {}
      );

      mockProc.stdout.emit("data", Buffer.from("Hello world\n"));
      mockProc.stdout.emit("data", Buffer.from("How are you\n"));
      mockProc.emit("close", 0);

      const result = await handle.promise;
      expect(result).toBe("Hello world How are you");
    });

    it("should call onFinal for finalized lines", async () => {
      const onFinal = vi.fn();
      const handle = await streamTranscribe(
        {
          modelPath: "/path/to/model.bin",
          language: "en",
          maxDuration: 30,
        },
        { onFinal }
      );

      mockProc.stdout.emit("data", Buffer.from("Hello\n"));
      expect(onFinal).toHaveBeenCalledWith("Hello");

      mockProc.emit("close", 0);
      await handle.promise;
    });

    it("should call onPartial for partial updates", async () => {
      const onPartial = vi.fn();
      const handle = await streamTranscribe(
        {
          modelPath: "/path/to/model.bin",
          language: "en",
          maxDuration: 30,
        },
        { onPartial }
      );

      // Send a partial (no \n, just \r)
      mockProc.stdout.emit("data", Buffer.from("Hel\r"));
      expect(onPartial).toHaveBeenCalledWith("Hel");

      mockProc.emit("close", 0);
      await handle.promise;
    });

    it("should stop after consecutive blank audio lines", async () => {
      const onSilence = vi.fn();
      // Use mockKill to detect SIGTERM
      mockKill.mockImplementation(() => {
        // Simulate process exit after kill
        setTimeout(() => mockProc.emit("close", null), 0);
      });

      const handle = await streamTranscribe(
        {
          modelPath: "/path/to/model.bin",
          language: "en",
          maxDuration: 30,
          silenceBlankCount: 2,
        },
        { onSilence }
      );

      mockProc.stdout.emit("data", Buffer.from("[BLANK_AUDIO]\n[BLANK_AUDIO]\n"));

      const result = await handle.promise;
      expect(onSilence).toHaveBeenCalled();
      expect(mockKill).toHaveBeenCalledWith("SIGTERM");
      expect(result).toBe("[No speech detected]");
    });

    it("should reset blank counter on non-blank lines", async () => {
      const onSilence = vi.fn();

      const handle = await streamTranscribe(
        {
          modelPath: "/path/to/model.bin",
          language: "en",
          maxDuration: 30,
          silenceBlankCount: 3,
        },
        { onSilence }
      );

      // Two blanks, then real text, then close
      mockProc.stdout.emit("data", Buffer.from("[BLANK_AUDIO]\n[BLANK_AUDIO]\n"));
      mockProc.stdout.emit("data", Buffer.from("Hello\n"));
      expect(onSilence).not.toHaveBeenCalled();

      mockProc.emit("close", 0);
      const result = await handle.promise;
      expect(result).toBe("Hello");
    });

    it("should stop on maxDuration timeout", async () => {
      vi.useFakeTimers();

      mockKill.mockImplementation(() => {
        setTimeout(() => mockProc.emit("close", null), 0);
      });

      const handlePromise = streamTranscribe(
        {
          modelPath: "/path/to/model.bin",
          language: "en",
          maxDuration: 5,
        },
        {}
      );

      // Advance past the "which" command resolution
      await vi.advanceTimersByTimeAsync(10);

      const handle = await handlePromise;

      // Advance past maxDuration
      await vi.advanceTimersByTimeAsync(5000);

      expect(mockKill).toHaveBeenCalledWith("SIGTERM");

      // Let the close event fire
      await vi.advanceTimersByTimeAsync(10);

      const result = await handle.promise;
      expect(result).toBe("[No speech detected]");

      vi.useRealTimers();
    });

    it("should handle process error", async () => {
      const handle = await streamTranscribe(
        {
          modelPath: "/path/to/model.bin",
          language: "en",
          maxDuration: 30,
        },
        {}
      );

      mockProc.emit("error", new Error("spawn failed"));

      await expect(handle.promise).rejects.toThrow("whisper-stream error: spawn failed");
    });

    it("should return a stop function that SIGTERMs the process", async () => {
      mockKill.mockImplementation(() => {
        setTimeout(() => mockProc.emit("close", null), 0);
      });

      const handle = await streamTranscribe(
        {
          modelPath: "/path/to/model.bin",
          language: "en",
          maxDuration: 30,
        },
        {}
      );

      // Emit some speech first
      mockProc.stdout.emit("data", Buffer.from("Hello world\n"));

      // Call the external stop
      handle.stop();

      expect(mockKill).toHaveBeenCalledWith("SIGTERM");

      const result = await handle.promise;
      expect(result).toBe("Hello world");
    });

    it("should resolve with accumulated text when stop is called", async () => {
      mockKill.mockImplementation(() => {
        setTimeout(() => mockProc.emit("close", null), 0);
      });

      const handle = await streamTranscribe(
        {
          modelPath: "/path/to/model.bin",
          language: "en",
          maxDuration: 30,
        },
        {}
      );

      // No speech — stop immediately
      handle.stop();

      const result = await handle.promise;
      expect(result).toBe("[No speech detected]");
    });
  });
});
