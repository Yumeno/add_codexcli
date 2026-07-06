---
name: list-codex-models
description: Codex CLIが認識している利用可能なモデル名を一覧表示する。
---

# list-codex-models

workspaceの`scripts/list-codex-models.*`、なければ
`{{SCRIPTS_ROOT}}/list-codex-models.*`を実行する。

- Windows: `powershell -ExecutionPolicy Bypass -NoProfile -File "<scripts-root>\list-codex-models.ps1"`
- Linux、macOS、WSL: `bash "<scripts-root>/list-codex-models.sh"`

ユーザー要求に`json`または`bundled`があれば対応するoptionを渡す。
`[CODEX_WRAPPER_ERROR]`はモデル一覧として扱わず、失敗として報告する。
