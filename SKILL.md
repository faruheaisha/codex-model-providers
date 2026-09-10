---
name: codex-model-providers
description: Set up, switch, and verify model providers in Codex (CLI or desktop app) — keep the built-in OpenAI/ChatGPT path while adding an OpenAI-compatible third party such as DeepSeek, Kimi, GLM, a gateway, or a local Ollama/LM Studio server. Covers model_providers tables, model catalogs, profile files, and switcher scripts. Use when Codex must run a non-OpenAI model, when GPT and another provider should both stay usable, or when such a setup needs debugging. Not for choosing among OpenAI-hosted models or general Codex CLI usage.
---

# Codex Model Providers

Goal: a working, verified setup where Codex can run the built-in OpenAI/ChatGPT path **and** at least one third-party provider, with a switching story the user can actually operate.

## Ground truth: what decides the provider

Four config keys in `$CODEX_HOME/config.toml` (default `~/.codex/config.toml`) decide everything:

| Key | Meaning |
| --- | --- |
| `model` | Model slug Codex sends to the provider |
| `model_provider` | Provider id; unset means the built-in `openai` provider |
| `model_providers.<id>` | Custom provider: `base_url`, `wire_api`, auth, headers |
| `model_catalog_json` | Optional catalog that replaces the model picker contents |

Consequences that shape every setup:

- **The provider is global, not per model.** Catalog entries carry no provider field, and the desktop app has no provider picker — its `thread/start` always passes `modelProvider: null`, so the config value wins. "Using both" therefore means *both defined, one active, switch before starting a task*. Do not promise mixing providers inside one task.
- **Profile files switch the CLI.** `$CODEX_HOME/<name>.config.toml` is a layer over the base config, selected with `codex --profile <name>`. They override keys but cannot delete them, so keep provider-specific keys out of the base layer.
- **The desktop app re-reads `config.toml`.** Verified: after editing the file, app-server `config/read` returns the new values and a fresh `thread/start` binds the new provider. A task already running keeps its provider. If the model picker still shows the old list, restart the app.
- **Auth is separate from providers.** A ChatGPT (subscription) login and custom providers coexist: each provider uses its own key/token. Keep `auth.json` untouched.

Details, verified key lists, and evidence: [references/codex-provider-facts.md](references/codex-provider-facts.md).

## Workflow

### 1. Inspect before editing

- Read `$CODEX_HOME/config.toml` and note the four keys above plus any provider-specific keys already present (`service_tier`, `web_search`, extra headers).
- `codex doctor` — reports the loaded model, provider, auth mode, and `config.toml parse ok`.
- `codex debug models` — shows the catalog actually in effect (ignores `--profile`; use it for the base config only).
- Confirm a backup exists before writing. Never paste a real API key into a repo, an issue, or a chat transcript.

### 2. Pick the switching story

| Situation | Approach |
| --- | --- |
| Terminal/scripts only | One base config + one `--profile` file per provider |
| Desktop app | Keep both providers in one `config.toml`, switch the top-level keys with a script, then start a new task |
| Secrets must stay out of the file | `env_key` on the provider + a user environment variable |

The desktop app is the common case; `scripts/codex-switch.ps1` (Windows) and `scripts/codex-switch.sh` (macOS/Linux) implement it with a small preset map, so the user edits JSON instead of TOML.

### 3. Write the files

Base config keeps the OpenAI path clean; the third-party provider is fully defined but not selected:

```toml
model = "gpt-5.6-sol"

[model_providers.deepseek]
name = "deepseek"
base_url = "https://api.deepseek.com/"
wire_api = "responses"
env_key = "DEEPSEEK_API_KEY"      # preferred over experimental_bearer_token
```

`$CODEX_HOME/deepseek.config.toml` (used as `codex --profile deepseek`):

```toml
model = "deepseek-flash"
model_provider = "deepseek"
model_catalog_json = "C:/Users/me/.codex/model-catalog.deepseek.json"
web_search = "disabled"
```

The catalog must expose exactly the slugs the user will see, and the slug is what gets sent upstream. Start from [assets/model-catalog.deepseek.json](assets/model-catalog.deepseek.json) (a field-minimal, parse-verified entry pair) and copy `model_messages.instructions_template` from a stock entry, because the catalog entry's instructions are the model's system prompt. Full walkthrough: [references/deepseek-case.md](references/deepseek-case.md).

### 4. Verify for real — do not stop at "config parses"

Run a cheap request through each path and read the header Codex prints:

```bash
codex exec --skip-git-repo-check --sandbox read-only "reply OK"
codex exec --profile deepseek --skip-git-repo-check --sandbox read-only "reply OK"
```

The header must show the expected `model:` and `provider:`. A 401/400 here means the key, base URL, wire API, or slug is wrong — fix it before reporting success. `codex doctor` and `codex debug models` cover the config layer; only a real request proves the provider layer.

### 5. Hand off

State plainly: which provider is active now, the exact switch command, that a **new task** is required, where the backups are, and how to roll back (restore the backed-up `config.toml`).

## Traps

- **Reserved provider ids.** `openai`, `ollama`, `lmstudio` cannot be redefined; pick a new id.
- **`wire_api`** accepts only `responses`; Chat Completions support is deprecated. A provider that only speaks Chat Completions needs a translating gateway.
- **Do not leak provider-specific keys into the base layer.** Everything in the base config applies in every profile. `service_tier = "default"`, for example, is sent to third-party endpoints too and can come back as HTTP 400.
- **`preferred_auth_method = "apikey"` / `forced_login_method = "api"`** block ChatGPT-subscription models. Remove them when the GPT path must work; a provider carrying its own token does not need them.
- **Slug is not a friendly name.** If the provider rejects a slug, set it to the provider's own model id.
- **`web_search`** must be off for providers without Codex's standalone search endpoint (the capability defaults to `false` for custom providers).
- **Secrets.** `env_key` is the documented choice; `experimental_bearer_token` is documented as discouraged and lands in plaintext. If a key is already inline, leave it alone unless the user asks, and never copy it into a repository.
- **`model_catalog_json` is global.** While it points at a third-party catalog, GPT models disappear from the picker; remove the key — not just the model — when switching back.
- **TOML strings escape backslashes.** A script that expands `~` into a Windows path and writes `key = "C:\Users\..."` breaks parsing with *"too few unicode value digits"*. Escape `\` (or emit forward slashes) whenever a generated value can contain a path.

## Scripts

Both scripts read presets from `$CODEX_HOME/provider-presets.json` (written with defaults on first run) and rewrite only the top-level keys a preset defines; `null` removes a key.

```powershell
.\codex-switch.ps1 -List
.\codex-switch.ps1 -Preset deepseek      # then start a new task
.\codex-switch.ps1 -Status
.\codex-switch.ps1 -Preset gpt -Restart  # restarts the desktop app too
```

```bash
./codex-switch.sh --preset deepseek
./codex-switch.sh --list
```

Every write is preceded by a timestamped copy of `config.toml` under `$CODEX_HOME/backups/`.

## References

- [references/codex-provider-facts.md](references/codex-provider-facts.md) — config keys with defaults, catalog entry fields, auth interaction, precedence, plus the verification commands and how each fact was established.
- [references/deepseek-case.md](references/deepseek-case.md) — end-to-end DeepSeek + GPT setup, including a two-model catalog and the exact commands used to prove both paths.
- [references/sources.md](references/sources.md) — official OpenAI documentation and community projects worth reading before inventing a workaround.
