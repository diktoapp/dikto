import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { loadConfig } from "./config.js";
import { streamTranscribe } from "./stream-transcriber.js";
import { StatusIndicator } from "./indicator.js";

export function createServer(): McpServer {
  const server = new McpServer({
    name: "sotto",
    version: "1.0.0",
  });

  // Register the "listen" tool — live streaming transcription
  server.tool(
    "listen",
    "Record audio from the microphone and transcribe it to text in real-time using whisper.cpp. " +
      "Shows live text as you speak. Use this tool when the user wants to provide voice input instead of typing.",
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
    async ({ maxDuration, language }, extra) => {
      const config = await loadConfig();
      const indicator = new StatusIndicator();

      try {
        indicator.show("listening");

        const { promise, stop } = await streamTranscribe(
          {
            modelPath: config.modelPath,
            language: language ?? config.language,
            maxDuration: maxDuration ?? config.maxDuration,
          },
          {
            onPartial(partial) {
              indicator.sendText(partial);
              try {
                void extra.sendNotification({
                  method: "notifications/progress",
                  params: {
                    progressToken: "listen",
                    progress: 0,
                    total: 1,
                    message: partial,
                  },
                });
              } catch {
                // notification sending is best-effort
              }
            },
            onFinal(line) {
              indicator.sendText(line);
              try {
                void extra.sendNotification({
                  method: "notifications/progress",
                  params: {
                    progressToken: "listen",
                    progress: 0,
                    total: 1,
                    message: line,
                  },
                });
              } catch {
                // notification sending is best-effort
              }
            },
            onSilence() {
              indicator.update("transcribing");
            },
          }
        );

        indicator.onStop(() => stop());

        const text = await promise;

        return {
          content: [
            {
              type: "text" as const,
              text,
            },
          ],
        };
      } catch (error) {
        const message =
          error instanceof Error ? error.message : String(error);

        if (message.includes("whisper-stream is not installed")) {
          return {
            content: [
              {
                type: "text" as const,
                text: "whisper-stream is not installed. Install it with: brew install whisper-cpp",
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
              text: `Live transcription failed: ${message}`,
            },
          ],
          isError: true,
        };
      } finally {
        indicator.close();
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
