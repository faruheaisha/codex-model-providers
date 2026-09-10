# Can GPT and DeepSeek appear side by side in the model list?

Short answer as of 2026-09-10 (Codex 0.153.4, desktop app 26.903.8094.0): **no, not through Codex configuration alone.** A side-by-side list needs a local gateway that routes by model name. This page records the test that settles it and the existing implementations worth using instead of writing one.

## The decisive test

1. Merge the stock GPT catalog with the DeepSeek entries (`~/.codex/models_cache.json` + the third-party catalog) into one `model_catalog_json`.
2. Confirm the picker-side effect: `codex -c model_catalog_json="<merged>" debug models` lists all nine slugs, GPT and DeepSeek together.
3. Run a real request for a third-party slug while the config is on the ChatGPT path:

```bash
codex exec -c model_catalog_json="<merged>" -c model="deepseek-flash" \
  --skip-git-repo-check --sandbox read-only "reply OK"
```

Result:

```
model: deepseek-flash
provider: openai
ERROR: status 400 ... "The 'deepseek-flash' model is not supported
when using Codex with a ChatGPT account."
```

The catalogue made the model *visible*; the provider still came from `model_provider`. That is the whole limitation in one line: **the picker is provider-agnostic, the config is not.**

## Why it works this way

- Catalog entries carry no provider field (`slug`, `display_name`, `supported_reasoning_levels`, `shell_command`, … — nothing that selects an endpoint).
- The desktop app sends `modelProvider: null` on `thread/start`, so the config value always wins.
- Profiles and project config can change which provider is active, but never per model.

Details: [codex-provider-facts.md](codex-provider-facts.md).

## What a merged list would require

```text
Codex (single provider, single catalog)
        │
        ▼
http://127.0.0.1:PORT/v1          ← one OpenAI-compatible gateway
        ├── gpt-*        → OpenAI / ChatGPT backend
        └── deepseek-*   → https://api.deepseek.com
```

Plus a merged `model_catalog_json` whose slugs are the gateway's model names. This is the architecture the community projects below all share; the codex-provider-manager README states it plainly ("the local proxy routes each model to its own provider").

## Existing implementations (prefer these over a custom proxy)

Snapshot 2026-09-10; star counts and platform support move.

| Project | ★ | License | What it gives you | Caveats |
| --- | --- | --- | --- | --- |
| [AITabby/codexsplit](https://github.com/AITabby/codexsplit) | 717 | none published | Built for the Codex desktop app: local gateway on `127.0.0.1:8765` plus a "Desktop Bridge" mode that puts third-party models into the **desktop model menu** while the official GPT path stays native; Chinese docs; provider presets reused from CC Switch | Windows build is the older `v1.2.0` EXE (macOS is `v2.0.1`), closed source, and enabling Bridge restarts Codex |
| [JiangNanGenius/Codex-Enhance-Manager](https://github.com/JiangNanGenius/Codex-Enhance-Manager) | 28 | Apache-2.0 | Windows + Apple-silicon macOS control panel; keeps official login while running a local proxy, provider credentials, Responses↔Chat adaptation, model mapping | Low adoption; slower release cadence |
| [PAIArtCom/Clipal](https://github.com/PAIArtCom/Clipal) | 147 | see its README | Go single binary, cross-platform reverse proxy; OAuth upstreams including **Codex/ChatGPT** with automatic token refresh; can take over the Codex CLI config from a web UI | Aimed at the CLI; wiring the desktop menu still needs the merged catalog |
| [OpenMined/alex](https://github.com/OpenMined/alex) | 80 | Apache-2.0 | Local proxy joining multiple subscriptions (ChatGPT/Codex, Claude, Gemini, Kimi…) and harnesses; subscription passthrough direction | Windows build is alpha |
| [decolua/9router](https://github.com/decolua/9router) | 28k | MIT | General-purpose gateway with 40+ upstreams, aimed at Codex/Cursor/Claude | You supply the desktop wiring and an OpenAI API key |
| [farion1231/cc-switch](https://github.com/farion1231/cc-switch) | 132k | MIT | The most established multi-provider **switcher** (its provider presets are the ones CodexSplit ships) | Switching, not merging: the picker still shows only the active provider's models |

## The tradeoff that decides the choice

Routing GPT through a gateway means either:

1. an OpenAI **API key** (per-token billing, separate from the ChatGPT subscription), or
2. a gateway that relays the **ChatGPT subscription** credentials (what CodexSplit's account pool and Clipal's OAuth upstreams exist to do).

Without an API key in `auth.json`, option 2 is the only way to keep subscription-backed GPT inside a merged list. Generic gateways (9router, LiteLLM, plain reverse proxies) only do option 1.

## When to revisit

Recheck after Codex upgrades: if a future version adds a provider field to catalog entries, or a provider picker, this page is obsolete. Until then, the switching setup in this skill stays the zero-dependency answer, and a gateway is an extra local service the user must keep running.

## Verified evidence log

| Step | Command | Outcome |
| --- | --- | --- |
| Merged catalog parses | `codex -c model_catalog_json="<merged>" debug models` | 7 GPT + 2 DeepSeek slugs listed |
| Routing is config-bound | `codex exec -c model_catalog_json="<merged>" -c model="deepseek-flash" ...` | Request went to `provider: openai`, HTTP 400 "not supported when using Codex with a ChatGPT account" |
