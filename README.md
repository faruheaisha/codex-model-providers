# codex-model-providers

一个 Codex Skill：让 Codex **同时保留 GPT（ChatGPT 订阅）和第三方 OpenAI 兼容模型**（DeepSeek / Kimi / GLM / 网关 / 本地 Ollama…），并且给你一个能真正操作的切换方式。

用一句话概括它解决的问题：装了第三方模型之后，GPT 从 Codex 里消失了；或者反过来 —— 每次换模型都要手动改 `config.toml`，还容易改坏。

## 先说清楚一条硬事实

Codex 的模型供应商是**全局单值**（`config.toml` 里的 `model_provider`）：

- 模型目录（`model_catalog_json`）的条目里**没有**供应商字段；
- 桌面 App 的 `thread/start` 永远传 `modelProvider: null`，也就是完全听配置的；
- App 里没有「按模型切换供应商」的界面。

所以这个 skill 做的是**两条链路都配好、随时切换、切换后新开任务生效**，而不是在同一条任务里混用两个供应商。社区项目（[codexsync](https://github.com/zssggle-rgb/codexsync)、[Codex-API-Switcher](https://github.com/AutoGavy/Codex-API-Switcher)）走的是同一条路。

## 内容

```text
codex-model-providers/
├── SKILL.md                                  # 给 Codex 用的主指令
├── agents/openai.yaml                        # UI 元数据
├── assets/
│   └── model-catalog.deepseek.json           # 字段最小化、已通过解析验证的目录模板
├── references/
│   ├── codex-provider-facts.md               # 配置键、目录 schema、鉴权交互、热加载实测
│   ├── deepseek-case.md                      # GPT + DeepSeek 的完整落地案例
│   ├── merged-model-picker.md                # 为什么「GPT 和 DeepSeek 并列显示」不能只靠配置，以及现成网关
│   └── sources.md                            # 官方文档 + 社区项目出处
└── scripts/
    ├── codex-switch.ps1                      # Windows 切换脚本
    └── codex-switch.sh                       # macOS / Linux 切换脚本
```

## 安装

把整个目录放进 Codex 的 skills 目录即可：

```bash
git clone https://github.com/faruheaisha/codex-model-providers "${CODEX_HOME:-$HOME/.codex}/skills/codex-model-providers"
```

Windows PowerShell：

```powershell
git clone https://github.com/faruheaisha/codex-model-providers "$env:USERPROFILE\.codex\skills\codex-model-providers"
```

之后可以直接对 Codex 说：「把 DeepSeek 接到 Codex 上，同时保留 GPT」。

## 直接使用脚本

两个脚本共用一份人可读的 preset 文件 `$CODEX_HOME/provider-presets.conf`（首次运行自动生成），空值表示**删除**该键：

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

```powershell
# Windows
.\codex-switch.ps1 -List
.\codex-switch.ps1 -Preset deepseek
.\codex-switch.ps1 -Status
.\codex-switch.ps1 -Preset gpt -Restart
```

```bash
# macOS / Linux（只需要 bash + awk，兼容 macOS 自带 bash 3.2）
./codex-switch.sh --list
./codex-switch.sh --preset deepseek
./codex-switch.sh --status
```

每次写入前都会把 `config.toml` 备份到 `$CODEX_HOME/backups/`。

终端用户还有更轻的路子：不动配置文件，直接 `codex --profile deepseek`。

## 想要「GPT 和 DeepSeek 在同一个模型菜单里并列」怎么办

先说结论：**改配置做不到**。实测把一个同时包含 GPT 和 DeepSeek 的目录挂上去，菜单里确实能看到 9 个模型，但选中 DeepSeek 时请求仍然发往 OpenAI，报 `The 'deepseek-flash' model is not supported when using Codex with a ChatGPT account` —— 因为供应商来自 `model_provider`，和「选哪个模型」是解耦的。

要并列显示，必须让 Codex 只认**一个**本地网关，由网关按模型名分流。这件事社区已经做过，不用自己写代理：CodexSplit（专为 Codex Desktop 打造）、Codex-Enhance-Manager、Clipal、alex、9router 等，各自的取舍（尤其是"GPT 走 API key 还是能透传 ChatGPT 订阅"）都记在 [references/merged-model-picker.md](references/merged-model-picker.md)。

## 这个 skill 里哪些是实测结论

| 结论 | 怎么来的 |
| --- | --- |
| 供应商是全局单值、目录条目无 provider 字段 | 读 App 打包代码 + 目录 schema + `model/list` 返回字段 |
| 改 `config.toml` 后 app-server 会热加载 | 用临时 `CODEX_HOME` 起 `codex app-server`，运行中改配置，`config/read` 与 `thread/start` 都立刻用新供应商 |
| 目录条目的最小必填字段 | 递进式喂给 Codex，按它返回的 "missing field" 逐个补齐，直到解析通过 |
| `preferred_auth_method` / `forced_login_method` 会挡住 ChatGPT 模型 | 实测：删掉之后 GPT 链路才恢复 |
| 两条链路真的能跑 | `codex exec` 在 GPT / DeepSeek / profile / 指定目录 四种组合下都拿到了正确的 `model:` + `provider:` 和真实回复 |

细节见 [references/codex-provider-facts.md](references/codex-provider-facts.md)。

## 参考来源

- 官方：[Config reference](https://developers.openai.com/codex/config-reference)、[Advanced configuration](https://developers.openai.com/codex/config-advanced)（profiles、自定义 provider、命令式 token）、[Models](https://developers.openai.com/codex/models)、[Authentication](https://developers.openai.com/codex/auth)、[openai/codex](https://github.com/openai/codex)
- 供应商侧：[DeepSeek API 文档](https://api-docs.deepseek.com/)（明确写着 OpenAI/Anthropic 兼容，OpenAI base_url = `https://api.deepseek.com`）、[Using the Responses API](https://api-docs.deepseek.com/guides/responses_api)
- 社区：[codexsync](https://github.com/zssggle-rgb/codexsync)、[Codex-API-Switcher](https://github.com/AutoGavy/Codex-API-Switcher)、[codex-provider-manager](https://github.com/korshunkov/codex-provider-manager)

## 安全提醒

- 优先用 `env_key` + 环境变量保存密钥；`experimental_bearer_token` 是明文，官方文档本身也不推荐。
- 切换脚本只改 `model` / `model_provider` / `model_catalog_json` / `web_search` 这类顶层键，不会重写整份配置，也不会动 `auth.json`。
- 本仓库不含任何真实密钥。

## License

MIT
