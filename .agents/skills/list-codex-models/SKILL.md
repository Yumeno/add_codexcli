---
name: list-codex-models
description: Codex CLIで利用できるモデルの確認方法と、codex-wrapperの現在のモデル設定を表示する。ユーザーがCodexのモデル一覧、利用可能モデル、現在のwrapper設定を尋ねた場合に使う。
---

# Codexモデル設定を確認する

`codex debug models` で利用可能モデルを確認する。この `SKILL.md` のディレクトリ直下の `scripts/` を絶対パスへ解決し、OSに合う同梱helperを単独コマンドで実行する。`codex-wrapper` の `-ShowModel` で保存設定も表示する。現在の作業ディレクトリや共通 `$HOME/scripts` を前提にしない。

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File "<解決したscripts>\list-codex-models.ps1"
powershell -ExecutionPolicy Bypass -NoProfile -File "<解決したscripts>\codex-wrapper.ps1" -ShowModel
```

```bash
bash "<解決したscripts>/list-codex-models.sh"
bash "<解決したscripts>/codex-wrapper.sh" --show-model
```

各コマンドは単独で実行する。`list-codex-models` は `-Bundled` / `--bundled`（バイナリ同梱カタログのみ）や `-Json` / `--json`（raw JSON）を受け付ける。Codex CLIが完全なモデル一覧を提供しない場合、推測で一覧を作らない。CLIが示すモデル選択方法、現在保存されたwrapper設定、未設定時はCLI既定へ委ねることを区別して報告する。
