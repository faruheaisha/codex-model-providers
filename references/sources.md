# Sources

Everything below was fetched and used while building this skill (2026-09-10). Prefer these over blog posts, and re-check after Codex updates, since provider plumbing moves quickly.

## Official OpenAI

| Source | Why it matters |
| --- | --- |
| [Config reference](https://developers.openai.com/codex/config-reference) | Authoritative list of `model_provider`, every `model_providers.<id>.*` field and its default, `model_catalog_json`, `preferred_auth_method`, `forced_login_method` |
| [Advanced configuration](https://developers.openai.com/codex/config-advanced) | Profiles and `--profile`, custom provider examples, command-backed tokens, Amazon Bedrock, OSS mode, project-config restrictions |
| [Config basics](https://developers.openai.com/codex/config-basic) | Where config lives (`~/.codex/config.toml`), precedence, trust model |
| [Models](https://developers.openai.com/codex/models) | Model slugs and the statement that Codex can point at any provider supporting the Chat Completions or Responses APIs (Chat Completions deprecated) |
| [Authentication](https://developers.openai.com/codex/auth) | ChatGPT sign-in vs API key, and how that interacts with the active provider |
| [openai/codex](https://github.com/openai/codex) | The CLI source and its `docs/` folder (`config.md`, `authentication.md`, `skills.md`); the docs files now just redirect to the pages above |

## Official provider docs

| Source | Why it matters |
| --- | --- |
| [DeepSeek API docs](https://api-docs.deepseek.com/) | "The DeepSeek API uses an API format compatible with OpenAI/Anthropic"; `base_url (OpenAI) = https://api.deepseek.com` |
| [DeepSeek: Using the Responses API](https://api-docs.deepseek.com/guides/responses_api) | The surface Codex talks to when `wire_api = "responses"` |
| [DeepSeek: Using the Anthropic API](https://api-docs.deepseek.com/guides/anthropic_api) | Relevant when wiring the same key into Anthropic-shaped tools instead of Codex |

## Community projects (same problem, different tools)

| Project | Take-away |
| --- | --- |
| [zssggle-rgb/codexsync](https://github.com/zssggle-rgb/codexsync) | Switches Codex providers while preserving session history — confirms that switching, not per-task mixing, is the established model |
| [AutoGavy/Codex-API-Switcher](https://github.com/AutoGavy/Codex-API-Switcher) | Windows GUI that edits `config.toml` provider entries; useful when a user wants a click-driven switcher instead of a script |
| [korshunkov/codex-provider-manager](https://github.com/korshunkov/codex-provider-manager) | Local proxy approach that presents several upstream providers behind one OpenAI-compatible endpoint — the escape hatch if a provider cannot speak the Responses API directly |

## Local sources of truth on the machine

| Source | Command or path |
| --- | --- |
| Effective config + auth + health | `codex doctor` |
| Rendered catalog, including full instruction templates | `codex debug models` |
| Stock catalog cache (full entries, all fields) | `$CODEX_HOME/models_cache.json` |
| Current credentials and auth mode | `$CODEX_HOME/auth.json` (`auth_mode`, `tokens`) |
| CLI help for the flags used here | `codex --help`, `codex exec --help`, `codex debug --help` |
