# Personal Agent Preferences

## Subagent Delegation

Available custom subagents (via the Task tool): `glm`, `grok`, `cursor`, `worker`.

- `glm` — runs on GLM-5.2 (Ollama Cloud). Frontier-class open coding/agentic model (SWE-bench Pro 62.1, Terminal-Bench 2.1 81.0), roughly between Claude Opus 4.7 and Opus 4.8 in coding strength, with 1M context for long-horizon work. **Default choice** for delegated work: strongest reasoning/coding depth of the three, and I have higher usage limits on it.
- `grok` / `cursor` — both relay to CLIs currently running **Composer 2.5 Fast** (Cursor's model, ~third on the Coding Agent Index, SWE-Bench-Pro-Hard-AA 47%). Fast mode trades some depth for ~30% lower wall-clock time per task. **Prefer these when speed/latency matters more than maximum depth** — quick lookups, fast parallel cross-checks, time-sensitive parallel exploration — not as the default for deep or high-stakes work.

- **Eagerly delegate** non-trivial work to these subagents instead of doing it all yourself, defaulting to `glm` unless the task specifically benefits from speed (then use `grok`/`cursor`) or an independent second opinion (then use whichever of `grok`/`cursor` wasn't already tried).
- When a task has independent, parallelizable parts (e.g. exploring multiple areas of a codebase, getting a second opinion on a design/fix, running checks from a different model), issue multiple Task calls to these subagents **in the same response** rather than sequentially.
- Give each subagent the full task plus any necessary context in the prompt — they do not see this conversation.
- Use `worker` for general-purpose exploration/Q&A/research when a specialized subagent isn't a better fit.
- Still do simple, single-step tasks yourself; don't delegate trivial reads/edits.
