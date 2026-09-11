# Worked example: OpenCode Go (Zen) — `deepseek-v4.1-flash`

Second verified setup (Codex 0.153.4, Windows, 2026-09-11). It is the harder shape than the DeepSeek case: the provider is a **gateway** that only advertises a Chat Completions URL, and it **rejects requests that carry no session header**. Both obstacles had to be solved before Codex would talk to it.

## What the user hands you

```
base_url = https://opencode.ai/zen/go/v1/chat/completions
api key  = sk-...
model    = deepseek-v4.1-flash
```

OpenCode Go is a $10/month subscription gateway ("Console Go") serving open coding models. It is not one provider — it fronts deepseek, kimi, glm, qwen, minimax, mimo, grok, longcat, hy and others behind one key, so the same wiring works for any of [their model ids](https://opencode.ai/docs/go/).

## Step 1 — verify the key before touching any config

```powershell
Invoke-RestMethod -Uri 'https://opencode.ai/zen/go/v1/models' -Method Get `
  -Headers @{ Authorization = "Bearer $ocKey" }
```

A 200 with 37 entries (`owned_by: opencode`) proves the URL, the key, and the model id. Do this first: it separates "my config is wrong" from "the key is wrong" for the rest of the session.

## Step 2 — the `wire_api` wall

The obvious config is wrong, and Codex says so loudly:

```toml
[model_providers.opencode]
base_url = "https://opencode.ai/zen/go/v1"
wire_api = "chat"          # ← rejected
```

```
Error loading config.toml: `wire_api = "chat"` is no longer supported.
How to fix: set `wire_api = "responses"` in your provider config.
More info: https://github.com/openai/codex/discussions/7782
in `model_providers.opencode.wire_api`
```

This is a hard config-parse failure, not a runtime fallback — Codex will not start. Chat Completions support is gone; `responses` is the only accepted value.

The instinct at this point is "so I need a translating proxy". Check first — the same gateway is usually serving a Responses endpoint one path over:

```powershell
POST https://opencode.ai/zen/go/v1/responses
{"model":"deepseek-v4.1-flash","input":"say PONG","max_output_tokens":64}
```

→ 200, standard Responses payload (`object: response`, a `reasoning` item, an `output_text` item, `usage`). It never appeared in the provider's public docs table, which lists only `…/v1/chat/completions` for the DeepSeek entries. **Probe for `/responses` on the same base path before concluding a gateway is unusable** — it costs one request and avoids a proxy you do not need.

Two useful negatives from the same probe round: `https://opencode.ai/zen/responses` and `https://opencode.ai/zen/go/responses` are 404, and `https://opencode.ai/zen/v1/responses` answers `401 Model deepseek-v4.1-flash is not supported` — the Zen endpoint accepts GPT/Claude/Grok ids but not the Go models, which live under `/zen/go/`.

## Step 3 — the session header

With `wire_api = "responses"` the config parses, and every request then came back:

```
400 {"error":{"type":"MissingSessionID",
     "message":"Error from provider (Console Go): Request is missing
                x-opencode-session and cannot be routed efficiently."}}
```

Go bills and routes per conversation, so it requires a session identifier on every request. The error names `x-opencode-session`; that is not necessarily the only name it accepts. Measured, by sending one header at a time:

| Header | Result |
| --- | --- |
| *(none)* | 400 `MissingSessionID` |
| `session_id: <uuid>` | 200 |
| `session-id: <uuid>` | 200 |
| `x-session-id: <uuid>` | 200 |
| `conversation_id: <uuid>` | 400 |
| `x-codex-session-id: <uuid>` | 400 |
| `thread-id`, `x-client-request-id`, `originator` | 400 |

The provider docs settle it: OpenCode lists Codex under *Validated Clients* with "Go recognizes its native session header". So the question was only whether Codex really sends one — and to which name. Captured from a local `HttpListener` sitting behind a temporary `base_url`, here is what Codex actually puts on a `/responses` POST (Codex CLI 0.153.4):

```
session-id:     01a08f38-c5dc-7710-a902-8bd686780890
thread-id:      01a08f38-c5dc-7710-a902-8bd686780890
x-client-request-id: 01a08f38-c5dc-7710-a902-8bd686780890
x-codex-window-id:   01a08f38-c5dc-7710-a902-8bd686780890:0
x-codex-turn-metadata: {"session_id":"…","thread_id":"…","turn_id":"…",
                        "window_id":"…","agent_name":"/root","request_kind":"turn", …}
x-codex-beta-features: remote_compaction_v2
originator:      Codex Desktop
user-agent:      Codex Desktop/0.153.4 (Windows 10.0.26200; x86_64) dumb (codex_exec; 0.153.4)
accept:          text/event-stream
authorization:   Bearer <provider token>
```

`session-id` is in that list and Go accepts it, so **no `http_headers` entry is needed**. Set a static header only when the gateway demands a name Codex does not send; a hardcoded UUID is a last resort, because it collapses every conversation into one routing bucket and defeats the prompt-caching the header exists to enable.

The same probe also shows Codex issues `GET {base_url}/models?client_version=<ver>` on startup for custom providers, and that the request carries `originator: Codex Desktop`.

## Step 4 — files

`~/.codex/config.toml` (provider defined, not selected):

```toml
model = "gpt-5.6-sol"

[model_providers.opencode]
name = "opencode-go"
base_url = "https://opencode.ai/zen/go/v1/"   # trailing slash + "responses"
wire_api = "responses"
experimental_bearer_token = "sk-..."          # prefer env_key in real use
```

The trailing slash is load-bearing. Codex joins the wire path onto `base_url`; with the slash, `…/go/v1/` + `responses` = `…/go/v1/responses`. Drop it and the last segment is replaced instead of extended.

`~/.codex/opencode.config.toml` (CLI profile):

```toml
model = "deepseek-v4.1-flash"
model_provider = "opencode"
model_catalog_json = "C:/Users/me/.codex/model-catalog.opencode.json"
web_search = "disabled"
```

Preset for the switchers, in `~/.codex/provider-presets.conf`:

```ini
[opencode]
model = deepseek-v4.1-flash
model_provider = opencode
model_catalog_json = ~/.codex/model-catalog.opencode.json
web_search = disabled
```

### The catalog is what removes the warnings

Selecting the provider without a catalog runs, but prints two warnings on every start:

```
ERROR failed to refresh available models: … failed to decode models response:
      missing field `models` at line 1 column 3063;
      body: {"object":"list","data":[{"id":"minimax-m3", …}]}
WARN  Unknown model deepseek-v4.1-flash is used. This will use fallback model metadata.
```

Codex expects its own `{"models":[…]}` shape when it probes a custom provider's `/models`; OpenCode answers with the OpenAI `{"object":"list","data":[…]}` shape. It is non-fatal — requests go through and answers come back — but "fallback model metadata" is worth avoiding because the context window and reasoning levels are then guesses.

Setting `model_catalog_json` clears **both**: the slug is now known, and Codex no longer probes `/models`. Verified by diffing the same run before and after the catalog was added.

Start from [../assets/model-catalog.opencode.json](../assets/model-catalog.opencode.json), which is the field-minimal shape, and put the real system prompt in `model_messages.instructions_template` (copy it from `codex debug models` or `$CODEX_HOME/models_cache.json`). The working entry was produced by cloning a stock DeepSeek-family entry so the instruction template, tool mode, truncation policy and patch tool type all matched what Codex already ships, then changing `slug`, `display_name`, `description`, `priority`, `context_window` and `max_context_window`.

> The shipped catalog declares `context_window = 1048576` for `deepseek-v4.1-flash` only because the sibling DeepSeek entries in the same catalog declare it; the gateway does not report a window. Treat it as inherited, not measured, and lower it if you see truncation errors.

## Proof

| Check | Result |
| --- | --- |
| `GET /zen/go/v1/models` | 200, 37 ids including `deepseek-v4.1-flash` |
| `POST /zen/go/v1/chat/completions` | 200 once a session header is present |
| `POST /zen/go/v1/responses` | 200, Responses payload |
| `codex exec -c model_provider=opencode -c model=deepseek-v4.1-flash …` | `model: deepseek-v4.1-flash`, `provider: opencode`, answered `OK` |
| `codex exec --profile opencode …` | same, no warning lines |
| `codex-switch.ps1 -Preset opencode` then plain `codex exec …` | `model: deepseek-v4.1-flash`, `provider: opencode`, answered `OK` |
| Tool-calling smoke test (`workspace-write`, "create hello.txt with exact content") | model drove `apply_patch` + `exec_command` + an MCP tool; file verified as 11 bytes `4F 50 45 4E 43 4F 44 45 5F 4F 4B` |
| `codex-switch.ps1 -Preset gpt` | back to `gpt-5.6-sol` / `openai (built-in)` |

The tool-calling test matters more than the chat test for a non-OpenAI model: the catalog assigns it `apply_patch_tool_type = "freeform"`, and a model that cannot emit that shape is unusable in Codex even if it answers questions. It passed, and when the sandbox blocked both write paths it recovered through another available tool rather than failing the task.

## Caveats seen in practice

- `reasoning.effort` accepts `minimal`, `low`, `medium`, `high` and `max` on this endpoint — all five returned 200. The shipped catalog exposes `low` / `high` / `max` to match its sibling entries.
- Reasoning tokens are billed and count against `max_tokens`/`max_output_tokens`. A 24-token cap produced an empty `content` with the thinking in `reasoning_content`, which looks like a broken model and is only a too-small budget.
- Go enforces per-model monthly caps with 5-hour and weekly sub-limits (DeepSeek V4.1 Flash: $15/month, $0.15–0.30 in, $0.60–1.20 out per 1M, off-peak/peak). Hitting a cap surfaces as a provider error mid-task, not as a Codex warning.
- The catalog is global: while `[opencode]` is active, GPT models are absent from the picker. That is the preset's job to restore.
- `experimental_bearer_token` keeps the key in plaintext in `config.toml`, same as the DeepSeek block. `env_key = "OPENCODE_API_KEY"` plus a user environment variable is the better shape — but a user-level variable is only visible to processes started after `setx`, so the desktop app needs a restart to see it.

## Other Go model ids (same wiring)

`deepseek-v4-pro`, `deepseek-v4-flash`, `deepseek-v4-flash-vision-exp`, `kimi-k3`, `kimi-k2.7-code`, `glm-5.3`, `glm-5.3-flash`, `qwen3.8-max`, `qwen3.8-flash`, `minimax-m3`, `mimo-v2.5-pro`, `grok-4.6`, `gpt-5.6-luna`, `longcat-2.0`, `hy3`, `muse-spark-1.3-contributor`.

Switch model without touching files: `codex-switch.ps1 -Preset opencode -Model kimi-k3`, or `codex exec --profile opencode -c model=kimi-k3 …` for a single run.
