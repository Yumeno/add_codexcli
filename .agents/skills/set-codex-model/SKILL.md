---
name: set-codex-model
description: codex-wrapperの既定モデルを表示または設定する。
---

# set-codex-model

workspaceの`scripts/codex-wrapper.*`、なければ`{{SCRIPTS_ROOT}}/codex-wrapper.*`を使う。

- モデル指定なし: `-ShowModel` / `--show-model`
- モデル指定あり: `-SetModel "<name>"` / `--set-model "<name>"`

WindowsではPowerShell版、Linux、macOS、WSLではbash版を実行する。
モデル名を推測せず、ユーザー指定値をそのままwrapperへ渡す。
`[CODEX_WRAPPER_ERROR]`は失敗として報告する。
