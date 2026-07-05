#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { AcpClient } from "./acp-client.mjs";

const ACP_COMMAND = process.env.ACP_COMMAND;
const ACP_ARGS = JSON.parse(process.env.ACP_ARGS ?? "[]");
const ACP_AUTH_METHOD = process.env.ACP_AUTH_METHOD || undefined;
const ACP_LABEL = process.env.ACP_LABEL || ACP_COMMAND;
const TOOL_NAME = process.env.ACP_TOOL_NAME || "prompt";
const SERVER_NAME = process.env.ACP_SERVER_NAME || `${ACP_COMMAND}-acp-bridge`;
const PROMPT_TIMEOUT_MS = Number(process.env.ACP_PROMPT_TIMEOUT_MS || 300_000);

if (!ACP_COMMAND) {
  console.error("ACP_COMMAND env var is required (the ACP agent binary to spawn).");
  process.exit(1);
}

let client = null;
let ready = null;

async function ensureClient(cwd) {
  if (client?.proc) return client;
  client = new AcpClient({ command: ACP_COMMAND, args: ACP_ARGS, cwd });
  client.start();
  ready = (async () => {
    await client.initialize();
    await client.authenticate(ACP_AUTH_METHOD);
  })();
  await ready;
  return client;
}

const server = new McpServer({ name: SERVER_NAME, version: "1.0.0" });

server.registerTool(
  TOOL_NAME,
  {
    title: `Ask ${ACP_LABEL}`,
    description:
      `Send a task/question to the real ${ACP_LABEL} CLI agent (spawned as an ACP subprocess, ` +
      `not a text-only wrapper) and return its final response. The agent runs with its own ` +
      `model, tools, and file/shell access scoped to the given working directory.`,
    inputSchema: {
      prompt: z.string().describe("The task or question to send to the agent."),
      cwd: z
        .string()
        .optional()
        .describe("Working directory for the agent session. Defaults to the bridge's cwd."),
    },
  },
  async ({ prompt, cwd }) => {
    const workDir = cwd || process.cwd();
    try {
      const c = await ensureClient(workDir);
      const sessionId = await c.newSession(workDir);
      const { text, stopReason } = await c.prompt(sessionId, prompt, {
        timeoutMs: PROMPT_TIMEOUT_MS,
      });
      const body = text.trim() || `(${ACP_LABEL} returned no text; stopReason=${stopReason})`;
      return { content: [{ type: "text", text: body }] };
    } catch (err) {
      client?.stop();
      client = null;
      return {
        content: [{ type: "text", text: `${ACP_LABEL} ACP bridge error: ${err.message}` }],
        isError: true,
      };
    }
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);

for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, () => {
    client?.stop();
    process.exit(0);
  });
}
