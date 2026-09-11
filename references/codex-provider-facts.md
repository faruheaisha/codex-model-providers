# Codex provider mechanics (verified)

Snapshot: Codex CLI 0.153.4, Codex desktop app 26.903.8094.0, Windows 11, 2026-09-10.
Re-check anything load-bearing with `codex debug models` and one real request after upgrading.

## Config keys that matter

From the official configuration reference (`model_provider`, `model_providers.*`, `model_catalog_json`):

| Key | Type / default | Notes |
| --- | --- | --- |
| `model_provider` | string, default `openai` | Provider id; must exist in `model_providers` |
| `model_catalog_json` | path | Replaces the model list Codex offers. A `$CODEX_HOME/<name>.config.toml` profile can override it per profile |
| `model_providers.<id>` | table | Custom provider definition. Built-in ids `openai`, `ollama`, `lmstudio` are reserved |
| `model_providers.<id>.base_url` | string | API base URL. Codex *joins* the wire path onto it, so the trailing slash decides whether the last segment is kept: `https://h/go/v1/` + `responses` → `https://h/go/v1/responses` |
| `model_providers.<id>.wire_api` | `responses` | Only accepted value. `chat` is a **config-parse failure**, not a fallback: *"`wire_api = \"chat\"` is no longer supported"* ([discussion 7782](https://github.com/openai/codex/discussions/7782)) |
| `model_providers.<id>.env_key` | string | Environment variable holding the API key (documented preference) |
| `model_providers.<id>.experimental_bearer_token` | string | Direct token; the reference itself calls this discouraged |
| `model_providers.<id>.requires_openai_auth` | bool, default `false` | Set when the endpoint authenticates with the OpenAI/ChatGPT account |
| `model_providers.<id>.http_headers` / `.env_http_headers` | map | Static or env-populated headers |
| `model_providers.<id>.query_params` | map | Extra query parameters on every request |
| `model_providers.<id>.request_max_retries` / `.stream_max_retries` / `.stream_idle_timeout_ms` | number | Defaults 4 / 5 / 300000 ms |
| `model_providers.<id>.supports_standalone_web_search` | bool, default `false` | Capability flag; the endpoint must also implement it |
| `model_providers.<id>.supports_websockets` | bool | Responses API WebSocket transport |
| `model_providers.<id>.auth` | table | Command-backed token helper (`command`, `args`, `cwd`, `timeout_ms`, `refresh_interval_ms`). Mutually exclusive with `env_key`, `experimental_bearer_token`, `requires_openai_auth` |

## Configuration precedence

Highest first (from the official docs): CLI flags and `--config` overrides → project `.codex/config.toml` (trusted projects only) → the `--profile` file → user `config.toml` → cloud-managed defaults → system config → built-in defaults.

Project-scoped config may **not** set `model_provider`, `model_providers`, `openai_base_url`, `chatgpt_base_url`, `profile(s)`, `notify`, or `otel` — Codex ignores those keys there and prints a startup warning. Provider setup therefore belongs in the user-level config.

## Profiles

- Files: `$CODEX_HOME/<name>.config.toml`, top-level keys only (do not nest them under `[profiles.<name>]` — that style is gone since 0.134.0).
- A profile is a layer: it can add or override keys, never delete them.
- `codex --profile <name>` works for `codex`, `codex exec`, `codex review`, `codex resume`, `codex queue`, `codex archive`, `codex delete`, `codex unarchive`, `codex fork`, `codex mcp`, `codex sandbox`, and `codex debug prompt-input`. It does **not** apply to `codex debug models` (verified from the CLI's own error message), so use a real request or a second config to check a profile.

## Model catalog

`model_catalog_json` points at `{"models": [ ... ]}`. Every entry must declare at least these fields — established by feeding Codex progressively richer entries and reading the parse errors it returns:

```json
{
  "slug": "deepseek-flash",
  "display_name": "DeepSeek-Flash",
  "description": "...",
  "default_reasoning_level": "high",
  "supported_reasoning_levels": [{ "effort": "high", "description": "high" }],
  "shell_type": "shell_command",
  "visibility": "list",
  "supported_in_api": true,
  "priority": 1,
  "support_verbosity": true,
  "truncation_policy": { "mode": "tokens", "limit": 10000 },
  "experimental_supported_tools": [],
  "model_messages": { "instructions_template": "..." }
}
```

- `model_messages.instructions_template` or `base_instructions` is required — a catalog entry without instructions fails with *"missing both `base_instructions` and `model_messages.instructions_template`"*. Copy the full template from a stock entry rather than writing a one-liner: it is the system prompt for that model.
- `default_reasoning_level` is optional but without it the picker shows no effort default.
- Entries with no `context_window` fall back to Codex's built-in metadata for the slug; set it explicitly for models Codex does not know.
- Useful optional fields: `input_modalities` (`["text"]` / `["text","image"]`), `supports_search_tool`, `web_search_tool_type`, `apply_patch_tool_type`, `model_messages.approvals`.
- **The catalog has no provider field.** `codex debug models` output and the app-server `model/list` entries expose `slug`/`id`/`model`, `displayName`, `description`, `supportedReasoningEfforts`, `isDefault` — never a provider. This is why one provider is active at a time.

## Auth interaction

- `auth.json` holds `auth_mode` (`chatgpt` or `apikey`) plus tokens. A ChatGPT sign-in and custom providers coexist: requests to a custom provider use that provider's `env_key`/token.
- `preferred_auth_method = "apikey"` and `forced_login_method = "api"` in `config.toml` pin authentication to the API-key path. With them present, ChatGPT-subscription models are unusable while `auth_mode` is still `chatgpt`. Remove both for a dual setup.
- `codex doctor` prints which auth path the active provider needs (`OpenAI auth is not required for the active model provider` for a token-carrying custom provider).

## Desktop app specifics

- The app spawns `codex -c features.code_mode_host=true app-server --analytics-default-enabled`. There is no profile or provider flag, and the only environment-driven config overrides are `CODEX_APP_SERVER_CHATGPT_BASE_URL` → `chatgpt_base_url` and `CODEX_APP_SERVER_OPENAI_BASE_URL` → `openai_base_url`.
- Per-thread parameters include `model`, `modelProvider`, `serviceTier`, and a `config` overlay. The app sends `modelProvider: null` for normal tasks, so `config.toml` decides; the only place it injects a provider is its built-in Copilot integration.
- The app writes a handful of settings back to `config.toml` (`mcp_servers.*.enabled`, `memories.*`, `windows.sandbox`, …) — not `model`/`model_provider`, so the switcher scripts do not fight the app.

## Hot reload

Measured with `codex app-server` over stdio while a temporary `CODEX_HOME` was in use:

1. `initialize`, then `config/read` → old model/provider.
2. Rewrite `config.toml` on disk.
3. `config/read` → new values; `thread/start` → the new model **and** the new provider id.

So an already-running app-server serves new tasks with the edited config; only the app's cached model list may lag, which a restart clears.

## What Codex actually sends (captured, not inferred)

Established by pointing a temporary provider at a local `HttpListener` and reading what arrived. The same technique is the fastest way to answer "does Codex send header X?" without trusting a changelog.

`GET {base_url}/models?client_version=0.153.4` — issued on every start for a custom provider:

```
authorization: Bearer <provider token>
accept: */*
originator: Codex Desktop
user-agent: Codex Desktop/0.153.4 (Windows 10.0.26200; x86_64) dumb
```

`POST {base_url}/responses` — one per turn attempt:

```
session-id:            <thread uuid>
thread-id:             <thread uuid>
x-client-request-id:   <thread uuid>
x-codex-window-id:     <thread uuid>:0
x-codex-turn-metadata: {"installation_id":…,"session_id":…,"thread_id":…,"turn_id":…,
                        "window_id":…,"agent_name":"/root","turn_id":…,
                        "request_kind":"turn","sandbox_mode":…,…}
x-codex-beta-features: remote_compaction_v2
accept:                text/event-stream
content-type:          application/json
authorization:         Bearer <provider token>
originator:            Codex Desktop
user-agent:            Codex Desktop/0.153.4 (…) dumb (codex_exec; 0.153.4)
```

Two consequences worth remembering:

- **Codex has a native session header: `session-id`.** A gateway that wants "the client's session id" may already be satisfied; check before hardcoding one. OpenCode Go accepts `session-id` (and `session_id`, `x-session-id`) and rejects requests without any of them, so it needed no `http_headers` at all.
- **Codex probes `/models` on custom providers and expects its own `{"models":[…]}` shape.** OpenAI-shaped `{"object":"list","data":[…]}` answers fail to decode and log `failed to refresh available models: … missing field 'models'`. It is non-fatal. Setting `model_catalog_json` stops the probe *and* resolves the slug, which also removes the `Unknown model … fallback model metadata` warning.

The request body is large (223 KB on the first turn of a bare `codex exec`, dominated by instructions and tool definitions), so gateways with tight request-size limits are worth testing early.

## Verification commands

| Purpose | Command | What to look for |
| --- | --- | --- |
| Config layer | `codex doctor` | `config.toml parse ok`, expected `model`, `default model provider`, auth mode |
| Catalog layer | `codex debug models` | Your slugs, and the fields Codex filled in for each entry |
| Provider layer | `codex exec --skip-git-repo-check --sandbox read-only "reply OK"` | Header line `model:` + `provider:` and a real answer |
| Profile layer | same with `--profile <name>` | Same, for the profile |
