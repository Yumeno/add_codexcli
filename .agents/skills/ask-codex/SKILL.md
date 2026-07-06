---
name: ask-codex
description: Codex CLIに質問を委任してセカンドオピニオンを取得する。ユーザーがask-codexを指定した場合や、Codexへ質問するよう求めた場合に使う。
---

# ask-codex

現在のユーザー要求をCodex CLIへ委任する。

1. workspaceの`scripts/codex-wrapper.*`が存在すればそれを使う。存在しなければ
   `{{SCRIPTS_ROOT}}/codex-wrapper.*`を使う。
2. Windowsでは次を実行する。
   ```powershell
   powershell -ExecutionPolicy Bypass -NoProfile -File "<scripts-root>\codex-wrapper.ps1" -Prompt "<質問>"
   ```
3. Linux、macOS、WSLでは次を実行する。
   ```bash
   bash "<scripts-root>/codex-wrapper.sh" --prompt "<質問>"
   ```
4. 必ずwrapperを実行し、自分自身で質問へ回答して代替しない。
5. `[CODEX_WRAPPER_ERROR]`が出た場合は失敗としてその内容を報告する。
6. 成功時はCodexの回答を示し、末尾に`*via Codex CLI*`と記載する。

追加のtool権限や`--dangerously-skip-permissions`を要求しない。実行時のpermission確認に従う。
