---
name: set-codex-model
description: codex-wrapper のデフォルトモデルを設定ファイルに保存・確認する。引数なしで現状表示、モデル名を渡すと保存。
disable-model-invocation: true
allowed-tools: Bash
---

# /set-codex-model — デフォルトモデルを設定する

`codex-wrapper.conf` にデフォルトモデル名を保存し、以後 `--model` 未指定でも
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

1. ラッパースクリプトのパスを特定:
```bash
WRAPPER_DIR="${CLAUDE_SKILL_DIR}/../../../scripts"
```

2. OS を判定して操作を分岐。`$ARGUMENTS` が空なら現状表示、非空なら保存:

```bash
ARG=$(echo "$ARGUMENTS" | tr -d '[:space:]')

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    if [[ -z "$ARG" ]]; then
        powershell -ExecutionPolicy Bypass -NoProfile -File "$WRAPPER_DIR/codex-wrapper.ps1" -ShowModel
    else
        powershell -ExecutionPolicy Bypass -NoProfile -File "$WRAPPER_DIR/codex-wrapper.ps1" -SetModel "$ARG"
    fi
else
    if [[ -z "$ARG" ]]; then
        bash "$WRAPPER_DIR/codex-wrapper.sh" --show-model
    else
        bash "$WRAPPER_DIR/codex-wrapper.sh" --set-model "$ARG"
    fi
fi
```

3. 結果を以下の形式で提示:

**引数なし（現状表示）の場合**:
```
## codex-wrapper の現在のモデル設定

(コマンドの出力をそのまま貼る。例: model=gpt-5.2-codex (source: config))

---
*変更するには `/set-codex-model <モデル名>`*
```

**引数ありで保存した場合**:
```
## codex-wrapper のデフォルトモデルを更新

保存先: (config_file のパス)
新しい既定モデル: (保存した値)

---
*以後 `/ask-codex` や `/ask-codex-with-context` で `--model` 未指定の場合、このモデルが使われます。*
```

4. エラー時（不正な文字を含むモデル名など）は exit code を確認し、stderr の内容をユーザーに提示する。
