import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { loadConfig } from "./config.js";
import { record, cleanupRecording } from "./recorder.js";
import { transcribe } from "./transcriber.js";
import { StatusIndicator } from "./indicator.js";

export function createServer(): McpServer {
  const server = new McpServer({
    name: "sotto",
    version: "1.0.0",
  });

  // Register the "listen" tool
  server.tool(
    "listen",
    "Record audio from the microphone and transcribe it to text using whisper.cpp. " +
      "Use this tool when the user wants to provide voice input instead of typing.",
    {
      maxDuration: z
        .number()
        .min(1)
        .max(120)
        .optional()
        .describe("Maximum recording duration in seconds (default: 30)"),
      language: z
        .string()
        .optional()
        .describe("Language code for transcription (default: en)"),
    },
    async ({ maxDuration, language }) => {
      const config = await loadConfig();

      const recordingOptions = {
        maxDuration: maxDuration ?? config.maxDuration,
        consecutiveFramesForSilence: config.consecutiveFramesForSilence,
        sileroVadSpeakingThreshold: config.sileroVadSpeakingThreshold,
      };

      const transcriptionOptions = {
        modelPath: config.modelPath,
        language: language ?? config.language,
      };

      let filePath: string | undefined;
      const indicator = new StatusIndicator();

      try {
        indicator.show("listening");
        const recording = await record(recordingOptions);
        filePath = recording.filePath;

        indicator.update("transcribing");
        const result = await transcribe(filePath, transcriptionOptions);

        return {
          content: [
            {
              type: "text" as const,
              text: result.text,
            },
          ],
        };
      } catch (error) {
        const message =
          error instanceof Error ? error.message : String(error);

        // Provide user-friendly error messages
        if (message.includes("speech-recorder native addon failed to load")) {
          return {
            content: [
              {
                type: "text" as const,
                text: "speech-recorder native addon failed to load. Try reinstalling: npm rebuild speech-recorder",
              },
            ],
            isError: true,
          };
        }

        if (message.includes("whisper-cpp is not installed")) {
          return {
            content: [
              {
                type: "text" as const,
                text: "whisper-cpp is not installed. Install it with: brew install whisper-cpp",
              },
            ],
            isError: true,
          };
        }

        if (message.includes("model not found") || message.includes("Model not found")) {
          return {
            content: [
              {
                type: "text" as const,
                text: "Whisper model not found. Run: sotto-setup",
              },
            ],
            isError: true,
          };
        }

        if (message.includes("permission") || message.includes("Permission")) {
          return {
            content: [
              {
                type: "text" as const,
                text: "Microphone access denied. Grant microphone access to your terminal in System Settings > Privacy & Security > Microphone.",
              },
            ],
            isError: true,
          };
        }

        return {
          content: [
            {
              type: "text" as const,
              text: `Recording/transcription failed: ${message}`,
            },
          ],
          isError: true,
        };
      } finally {
        indicator.close();
        if (filePath) {
          await cleanupRecording(filePath);
        }
      }
    }
  );

  // Register the "listen" prompt (creates the /mcp__sotto__listen slash command)
  server.prompt(
    "listen",
    "Use voice input — records from your microphone and transcribes speech to text",
    () => ({
      messages: [
        {
          role: "user",
          content: {
            type: "text",
            text:
              "I want to use voice input. Please call the `listen` tool to record audio from my microphone " +
              "and transcribe my speech. After you get the transcription, treat it as my message and respond to it directly.",
          },
        },
      ],
    })
  );

  return server;
}
