---
name: set-codex-model
description: codex-wrapper のデフォルトモデルを設定ファイルに保存・確認する。引数なしで現状表示、モデル名を渡すと保存。
disable-model-invocation: true
allowed-tools: Bash
---

# /set-codex-model — デフォルトモデルを設定する

`codex-wrapper.conf` にデフォルトモデル名を保存し、以後 `-Model` / `--model` 未指定でも
そのモデルが使われるようにします。引数なしで呼ぶと現状を表示します。

設定ファイルは **ラッパースクリプトと同じディレクトリ** に置かれます:
- プロジェクトインストール: `<proj>/scripts/codex-wrapper.conf`
- グローバルインストール: `~/.claude/scripts/codex-wrapper.conf`

> **解決順位（ラッパー側）:**
> 1. `--model` / `-Model` CLI 引数
> 2. `$CODEX_WRAPPER_MODEL` 環境変数
> 3. `codex-wrapper.conf` の `model=...`
> 4. 何もなければ codex CLI のデフォルト（不明なので表示しない）

## 引数の解釈

- 引数なし → 現状を表示
- 引数あり（モデル名 1 つ）→ 保存

利用可能なモデル名は `/list-codex-models` で確認できます。

## 手順

### 1. ラッパースクリプトを呼び出す

> **重要 (許可プロンプト回避):** wrapper を呼ぶときは
> **素の 1 コマンドで直接呼ぶこと。** 変数代入の前置やコマンド置換 (`OUTPUT=$(...)`) は
> 許可傘から外れて承認要求が出る。stdout はそのまま tool result に返るので捕捉不要。
> wrapper のパスは **必ず double quote で囲む**。

#### Windows + Claude Code (主用途)

**引数なし（現状表示）:**
```bash
powershell -ExecutionPolicy Bypass -NoProfile -File "$HOME/.claude/scripts/codex-wrapper.ps1" -ShowModel
```

**モデル名を渡して保存:**
```bash
powershell -ExecutionPolicy Bypass -NoProfile -File "$HOME/.claude/scripts/codex-wrapper.ps1" -SetModel "gpt-5.5"
```

不正な文字を含むモデル名は wrapper 側で拒否される (`^[A-Za-z0-9._:/-]+$` のみ許可)。

#### Linux/Mac native 環境

```bash
bash "$HOME/.claude/scripts/codex-wrapper.sh" --show-model
bash "$HOME/.claude/scripts/codex-wrapper.sh" --set-model "gpt-5.5"
```

### 2. 結果を以下の形式で提示

**引数なし（現状表示）の場合**:
```
## codex-wrapper の現在のモデル設定

(コマンドの出力をそのまま貼る。例: model=gpt-5.5 (source: config))

---
*変更するには `/set-codex-model <モデル名>`*
```

**引数ありで保存した場合**:
```
## codex-wrapper のデフォルトモデルを更新

保存先: (config_file のパス)
新しい既定モデル: (保存した値)

---
*以後 `/ask-codex` や `/ask-codex-with-context` で `--model` / `-Model` 未指定の場合、このモデルが使われます。*
```

### 3. エラー時の対応

不正な文字を含むモデル名等で wrapper が exit code 1 を返した場合、stderr の内容は
**通常運用 (素の 1 コマンド呼び) では tool result の混合 stream に出る**。
ユーザーには「モデル名の文字が許可されない (英数 / `.` / `_` / `:` / `/` / `-` のみ可)」旨を伝える。
