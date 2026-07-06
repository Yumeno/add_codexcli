---
name: ask-codex-with-context
description: ファイル、差分、履歴などの必要最小限のcontextを添えてCodex CLIへレビューや監査を依頼する。
---

# ask-codex-with-context

1. 現在のユーザー要求に必要なファイル、`git diff`、`git log`だけを収集する。
2. secretや無関係なファイルを含めない。送信内容をユーザー要求の範囲から拡大しない。
3. contextをUTF-8の一時ファイルへ保存する。
4. workspaceの`scripts/codex-wrapper.*`、なければ`{{SCRIPTS_ROOT}}/codex-wrapper.*`を使う。
5. Windows:
   ```powershell
   powershell -ExecutionPolicy Bypass -NoProfile -File "<scripts-root>\codex-wrapper.ps1" -Prompt "<質問>" -ContextFile "<context-file>"
   ```
6. Linux、macOS、WSL:
   ```bash
   bash "<scripts-root>/codex-wrapper.sh" --prompt "<質問>" --context-file "<context-file>"
   ```
7. 必ずwrapperを実行する。`[CODEX_WRAPPER_ERROR]`は失敗として報告する。
8. 成功時はCodexの回答と、OpenAIへ送信したcontextの種類を示す。
