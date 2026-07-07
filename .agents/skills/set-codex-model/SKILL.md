---
name: set-codex-model
description: codex-wrapperの既定モデルを保存または確認する。ユーザーがCodexの既定モデルを明示的に設定、変更、確認する場合に使う。
---

# Codexの既定モデルを設定する

モデル名はユーザー指定をそのまま使い、存在を推測しない。引数なしなら設定を表示する。この `SKILL.md` のディレクトリ直下の `scripts/` を絶対パスへ解決し、現在の作業ディレクトリや共通 `$HOME/scripts` を前提にしない。

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File "<解決したscripts>\codex-wrapper.ps1" -ShowModel
powershell -ExecutionPolicy Bypass -NoProfile -File "<解決したscripts>\codex-wrapper.ps1" -SetModel "model-name"
```

```bash
bash "<解決したscripts>/codex-wrapper.sh" --show-model
bash "<解決したscripts>/codex-wrapper.sh" --set-model "model-name"
```

保存先の既定は `$HOME/.agents/add_codexcli/codex-wrapper.conf` （Windowsでは `%USERPROFILE%\.agents\add_codexcli\codex-wrapper.conf`）。`CODEX_WRAPPER_CONFIG` 環境変数で上書きできる。

設定先と優先順位をwrapperの出力どおりに報告する。認証情報や他の設定を変更しない。
