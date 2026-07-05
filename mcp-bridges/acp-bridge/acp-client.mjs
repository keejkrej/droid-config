import { spawn } from "node:child_process";
import readline from "node:readline";

/**
 * Minimal Agent Client Protocol (ACP) client.
 * Speaks newline-delimited JSON-RPC 2.0 over stdio to an ACP agent
 * subprocess (e.g. `grok agent stdio`, `cursor-agent acp`).
 */
export class AcpClient {
  constructor({ command, args, cwd, env }) {
    this.command = command;
    this.args = args;
    this.cwd = cwd;
    this.env = env;
    this.proc = null;
    this.rl = null;
    this.nextId = 1;
    this.pending = new Map();
    this.authMethods = [];
  }

  start() {
    if (this.proc) return;
    this.proc = spawn(this.command, this.args, {
      cwd: this.cwd,
      env: { ...process.env, ...this.env },
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.proc.on("exit", (code, signal) => {
      const err = new Error(`ACP agent "${this.command}" exited (code=${code}, signal=${signal})`);
      for (const { reject } of this.pending.values()) reject(err);
      this.pending.clear();
      this.proc = null;
    });
    this.proc.stderr.on("data", () => {
      // Swallow agent stderr/log noise; surfaced only on failure via exit code.
    });
    this.rl = readline.createInterface({ input: this.proc.stdout });
    this.rl.on("line", (line) => this._handleLine(line));
  }

  _handleLine(line) {
    if (!line.trim()) return;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      return;
    }

    // Requests coming FROM the agent (e.g. permission prompts) need a reply.
    if (msg.method && msg.id !== undefined && !("result" in msg) && !("error" in msg)) {
      this._handleAgentRequest(msg);
      return;
    }

    // Notifications (no id): streamed session updates, etc.
    if (msg.method && msg.id === undefined) {
      this.onNotification?.(msg);
      return;
    }

    // Response to one of our requests.
    if (msg.id !== undefined) {
      const waiter = this.pending.get(msg.id);
      if (!waiter) return;
      this.pending.delete(msg.id);
      if (msg.error) waiter.reject(new Error(msg.error.message ?? JSON.stringify(msg.error)));
      else waiter.resolve(msg.result ?? {});
    }
  }

  _handleAgentRequest(msg) {
    if (msg.method === "session/request_permission") {
      const options = msg.params?.options ?? [];
      const chosen =
        options.find((o) => /allow.once/i.test(o.optionId ?? o.kind ?? ""))?.optionId ??
        options[0]?.optionId;
      this._reply(msg.id, { outcome: { outcome: "selected", optionId: chosen } });
      return;
    }
    // Unknown agent->client request: decline gracefully instead of hanging the agent.
    this._replyError(msg.id, -32601, `Method not supported by bridge: ${msg.method}`);
  }

  _reply(id, result) {
    this.proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");
  }

  _replyError(id, code, message) {
    this.proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }) + "\n");
  }

  request(method, params, timeoutMs = 120_000) {
    if (!this.proc) throw new Error("ACP agent process is not running");
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${method} timed out after ${timeoutMs}ms`));
      }, timeoutMs);
      this.pending.set(id, {
        resolve: (v) => {
          clearTimeout(timer);
          resolve(v);
        },
        reject: (e) => {
          clearTimeout(timer);
          reject(e);
        },
      });
      this.proc.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    });
  }

  async initialize() {
    const result = await this.request("initialize", {
      protocolVersion: 1,
      clientCapabilities: { fs: { readTextFile: false, writeTextFile: false }, terminal: false },
      clientInfo: { name: "factory-acp-bridge", version: "1.0.0" },
    });
    this.authMethods = (result.authMethods ?? []).map((m) => m.id);
    return result;
  }

  async authenticate(preferredMethodId) {
    const methodId =
      (preferredMethodId && this.authMethods.includes(preferredMethodId) && preferredMethodId) ||
      this.authMethods.find((m) => m === "cached_token") ||
      this.authMethods[0];
    if (!methodId) return; // Some agents don't require an explicit authenticate call.
    await this.request("authenticate", { methodId });
  }

  async newSession(cwd) {
    const { sessionId } = await this.request("session/new", { cwd, mcpServers: [] });
    return sessionId;
  }

  async prompt(sessionId, text, { timeoutMs } = {}) {
    let collected = "";
    const previousHandler = this.onNotification;
    this.onNotification = (msg) => {
      if (msg.method === "session/update") {
        const update = msg.params?.update;
        if (update?.sessionUpdate === "agent_message_chunk" && update.content?.text) {
          collected += update.content.text;
        }
      }
      previousHandler?.(msg);
    };
    try {
      const result = await this.request(
        "session/prompt",
        { sessionId, prompt: [{ type: "text", text }] },
        timeoutMs
      );
      return { text: collected, stopReason: result.stopReason };
    } finally {
      this.onNotification = previousHandler;
    }
  }

  stop() {
    this.rl?.close();
    this.proc?.kill();
    this.proc = null;
  }
}
