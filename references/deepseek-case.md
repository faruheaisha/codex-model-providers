# Worked example: GPT + DeepSeek in one Codex install

This is the setup that was built and verified end to end (Codex 0.153.4, Windows, 2026-09-10). It reproduces the common situation where a DeepSeek-only install has pushed GPT out of reach, and ends with both paths usable.

## Starting point

`~/.codex/config.toml` had been rewritten to a DeepSeek-only state:

```toml
model = "deepseek-flash"
model_provider = "deepseek"
preferred_auth_method = "apikey"
forced_login_method = "api"
web_search = "disabled"
model_catalog_json = "C:/Users/me/.codex/models.json"

[model_providers.deepseek]
name = "deepseek"
base_url = "https://api.deepseek.com/"
wire_api = "responses"
experimental_bearer_token = "sk-..."
```

Consequences: the GPT catalog was replaced by a two-entry DeepSeek catalog, and `forced_login_method = "api"` pinned auth away from the ChatGPT subscription, even though `auth.json` still said `auth_mode = "chatgpt"`.

## Target layout

| File | Role |
| --- | --- |
| `~/.codex/config.toml` | Base layer: GPT selected, DeepSeek provider defined but idle |
| `~/.codex/deepseek.config.toml` | CLI profile selected with `codex --profile deepseek` |
| `~/.codex/model-catalog.deepseek.json` | Two-entry catalog used only in DeepSeek mode |
| `~/.codex/provider-presets.conf` | Preset map used by `codex-switch.ps1` / `.sh` |
| `~/.codex/backups/` | Timestamped copies made by every switch |

## Base config header

```toml
model = "gpt-5.6-sol"
model_reasoning_effort = "high"
personality = "pragmatic"

# ... unrelated keys unchanged (notify, [desktop], [projects.*], [mcp_servers.*]) ...

[model_providers.deepseek]
name = "deepseek"
base_url = "https://api.deepseek.com/"
wire_api = "responses"
experimental_bearer_token = "sk-..."
```

Removed from the base on purpose:

- `model_provider` → unset, so the built-in `openai` provider is active.
- `model_catalog_json` → unset, so the stock GPT catalog returns.
- `web_search = "disabled"` → moved into the DeepSeek profile; GPT keeps the default.
- `preferred_auth_method`, `forced_login_method` → they block ChatGPT models.

`service_tier` stays out of the base entirely: it is a top-level key, profiles cannot delete it, and third-party endpoints can reject it with HTTP 400.

## Profile file

`~/.codex/deepseek.config.toml`:

```toml
model = "deepseek-flash"
model_provider = "deepseek"
model_reasoning_effort = "high"
model_catalog_json = "C:/Users/me/.codex/model-catalog.deepseek.json"
web_search = "disabled"
```

Use it as `codex --profile deepseek` (or `codex exec --profile deepseek "..."`). No file is touched, which makes this the safest switching path when only the terminal is involved.

## Catalog file

Take [../assets/model-catalog.deepseek.json](../assets/model-catalog.deepseek.json) and replace the two `model_messages.instructions_template` values with the full template from a stock entry — `codex debug models` prints the complete catalog, and `~/.codex/models_cache.json` holds the same entries. The slugs are the model ids sent to `https://api.deepseek.com/`; both `deepseek-flash` and `deepseek-v4-pro` were accepted by the endpoint as tested.

## Presets

`~/.codex/provider-presets.conf`:

```ini
[gpt]
model = gpt-5.6-sol
model_provider =
model_catalog_json =
web_search =

[deepseek]
model = deepseek-flash
model_provider = deepseek
model_catalog_json = ~/.codex/model-catalog.deepseek.json
web_search = disabled
```

Empty values mean "remove this key", which is what restores the stock GPT catalog. Add a preset per additional provider; the scripts manage the union of all preset keys, so nothing is left behind when switching.

## Proof

| Check | Result |
| --- | --- |
| `codex exec --skip-git-repo-check --sandbox read-only "reply OK"` | `model: gpt-5.6-sol`, `provider: openai`, answered |
| `codex exec --profile deepseek ...` | `model: deepseek-flash`, `provider: deepseek`, answered |
| `codex exec -c model_catalog_json=... -c model_provider=deepseek -c model=deepseek-v4-pro ...` | `model: deepseek-v4-pro`, `provider: deepseek`, answered |
| `codex debug models` (base config) | 7 stock models: `gpt-6-astra`, `gpt-reserve`, `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-5.5`, `codex-auto-review` |
| `codex doctor` | `config.toml parse ok`; auth stays `chatgpt`; provider reports "auth not required" in DeepSeek mode |
| Switcher round trip | `--preset deepseek` then `--preset gpt` changed only the four managed keys; tables such as `[model_providers.deepseek]` and all unrelated keys survived |

## Caveats seen in practice

- The DeepSeek key was already inline as `experimental_bearer_token`. It was left in place rather than rotated mid-task; switching it to `env_key = "DEEPSEEK_API_KEY"` plus a user environment variable is the better long-term shape.
- `notify`, `[desktop]`, `[projects.*]`, and MCP server tables were untouched — a switcher must never rewrite the whole file.
- The desktop app needed no restart to *use* the new provider for new tasks, but its model picker can keep showing the previous catalog until restarted.
