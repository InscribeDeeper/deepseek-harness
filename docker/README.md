# 在 Docker 里跑一个 dsh 实例

单容器部署 DeepSeek Harness 的 Web UI。镜像装的是 npm 上已发布的 `@deepseek-ai/dsh`（`alpha` dist-tag 跟随本仓库的预发布线），不在容器里编译 monorepo。

## 快速开始

```sh
cd docker
cp .env.example .env          # 填 DEEPSEEK_API_KEY
docker compose up -d --build
docker compose logs | grep 'dsh web:'
```

把日志里那条 `http://127.0.0.1:3080/?token=...` 粘到浏览器。token 换成签名 cookie 后重定向到 `/`，之后直接开 `http://127.0.0.1:3080/` 即可。

进 UI 后两步：**Settings → Models** 确认模型可用（`.env` 里给了 key 就已经能用），**Choose workspace** 选 `/workspace`，然后才能发消息。

## 这套编排解决的三个问题

**绑定地址。** `dsh web` 明确拒绝 `--host 0.0.0.0`——Web UI 能以容器用户的权限执行命令，它没有 TLS 也没有代理契约。所以服务只监听容器 loopback，`entrypoint.sh` 用 socat 在**同一个端口、容器网卡地址**上转发一层；宿主用 `-p 127.0.0.1:3080:3080` 映射。端口一致的好处是启动时打印的那条带 token 的 URL 在宿主浏览器里可以原样使用，Host 头仍是 `127.0.0.1:3080`，浏览器信任围栏和 cookie authority 都对得上。

用 `--network host` 时设 `DSH_WEB_PROXY=0`：那时 loopback 就是宿主的，再转发一层等于把 agent 暴露到局域网。

**状态。** 所有用户数据在 `$DSH_HOME`（镜像里是 `/data/dsh`），挂到 `./data/dsh-home`：会话、设置、凭据、profile，还有浏览器会话的签名密钥——所以容器重启后旧 cookie 依然有效，不用重新走 token。不挂这个卷，会话随容器一起消失。

**sandbox。** bash 工具走 `ctx.sandbox`，没有可用 runner 就 fail-closed（`SANDBOX_UNAVAILABLE`），不会静默地无约束执行。Linux 的选择链是 bwrap → landlock：默认 Docker 容器里 bwrap 建 namespace 会被拒（`--privileged` 或 `--security-opt seccomp=unconfined` 都救不了 AppArmor 那一层），但 **landlock 档实测 `full` 强制**，无需任何额外权限。所以镜像不装 bubblewrap。

## 验证功能

一次性任务（不进 UI，最快的冒烟）：

```sh
docker compose exec dsh dsh --profile headless "列出 /workspace 里的文件并总结这个项目"
```

没配 key 时它会明确报错退出，不会静默降级：

```
dsh: MISSING_CREDENTIAL: llm-deepseek: no API key for provider route "deepseek-official"; ...
```

换成真实项目做实验，改 `.env` 里的 `DSH_WORKSPACE` 指到项目目录，然后 `docker compose up -d`。注意这个目录是 agent 的爆炸半径，它可读可写。

`DSH_PERMISSION_MODE` 控制文件策略：`read-only` / `workspace-write`（默认，越界要审批）/ `danger-full-access`（不问）。

## 用 kris-agent 的本地模型代替 DeepSeek

`llm-pi-ai` 适配器接任何 OpenAI 兼容端点，kris-agent 的 `/v1/chat/completions` 正好是，且透传 `tools` / `tool_choice`（`kris-agent/src/openai.js:24`），流式也转发 tool_calls delta。

已验证可用的接法（`data/dsh-home/settings.yaml` + `cordis.patch.yml` 就是这套）：

- baseURL 走 `http://agent.kris-home/v1`。容器里没装 kris-home 私有 CA，443 会 `UNABLE_TO_VERIFY_LEAF_SIGNATURE`；8790 直连从容器网段也过不去；nginx 的 80 是通的。
- key 用 `ka_...`，以 `KRIS_AGENT_KEY` 环境变量名被 settings 引用，密钥本身只在 `.env` 里。
- 模型填**真实模型名**（`qwen2.5:14b-instruct-16384`），不要填 profile id —— profile 会插入自己的 system prompt 并注入知识库检索结果，污染 harness 的提示词。key 上绑定的模型在 OpenAI 路由不生效，以请求里的 `model` 为准。
- `compat` 两项必须写：Ollama 不认 `role:"developer"`，也只认 `max_tokens`。

**模型选择是硬约束**，实测：

| 模型 | tool_calls | 结论 |
|---|---|---|
| `qwen2.5:14b-instruct-16384` | 正常返回 | 可用，dsh 的读文件 / bash / 写文件全跑通 |
| `deepseek-r1:7b` | 返回 null，只吐白话「我无法访问文件」 | 不可用 |

16k 上下文仍是天花板：system prompt + 全套工具定义就占掉一大块，任务一大 Ollama 会**静默截断**，症状是不调工具、把 tool call 写成文本、瞎编。

## 需要知道的边界

- 镜像里没有浏览器，所以固定用 `--no-open`；URL 打印给宿主看。
- 容器内以 `node` 用户（uid 1000）运行，和宿主用户 uid 对齐，挂载卷不会出现 root 属主的文件。
- 换版本改 `.env` 里 `DSH_VERSION`（dist-tag 或确切版本号），然后 `docker compose build`。
- 要测**本仓库未发布的改动**，这套编排不适用——它装的是 npm 上的包。那种情况在宿主上 `pnpm run build && pnpm dsh web` 更直接。
