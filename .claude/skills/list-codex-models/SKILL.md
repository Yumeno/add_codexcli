---
name: list-codex-models
description: Codex CLI が認識しているモデル一覧を取得する。`--model` に渡せる値を確認したい時に使う。
disable-model-invocation: true
allowed-tools: Bash
---

# /list-codex-models — 利用可能なモデルを列挙する

`codex debug models` を呼び出して、Codex CLI が知っているモデル名を一覧表示します。
`/ask-codex` や `/ask-codex-with-context` で `--model` に何を渡せるか確認するためのスキル。

> **`disable-model-invocation` について:** デフォルトは `true`（手動起動のみ）。
> 自動呼び出しの必要性は低いので基本このままで OK。

## 引数の解釈

`$ARGUMENTS` は省略可能。以下のキーワードを含むと挙動が変わる:

- `bundled` / `オフライン` → `--bundled` を付ける（バイナリ同梱カタログのみ）
- `json` / `生` → `--json` を付ける（raw JSON 出力）
- それ以外 → 名前リスト（デフォルト）

## 手順

1. ヘルパースクリプトのパスを特定する:

```bash
HELPER_DIR="${CLAUDE_SKILL_DIR}/../../../scripts"
```

2. OS を判定して適切なヘルパーを呼び出す。`$ARGUMENTS` の中身に応じてオプションを組み立てる:

```bash
EXTRA_ARGS=()
if echo "$ARGUMENTS" | grep -qiE 'bundled|オフライン'; then
    EXTRA_ARGS+=(--bundled)
fi
if echo "$ARGUMENTS" | grep -qiE 'json|生'; then
    EXTRA_ARGS+=(--json)
fi

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    # PowerShell 側は -Bundled / -Json のスイッチに置換
    PS_ARGS=()
    for a in "${EXTRA_ARGS[@]}"; do
        case "$a" in
            --bundled) PS_ARGS+=(-Bundled) ;;
            --json)    PS_ARGS+=(-Json) ;;
        esac
    done
    OUTPUT=$(powershell -ExecutionPolicy Bypass -NoProfile -File "$HELPER_DIR/list-codex-models.ps1" "${PS_ARGS[@]}" 2>&1)
else
    OUTPUT=$(bash "$HELPER_DIR/list-codex-models.sh" "${EXTRA_ARGS[@]}" 2>&1)
fi
```

3. 結果を以下の形式でユーザーに提示する:

**名前リストの場合**:
```
## Codex CLI が認識しているモデル

(取得したモデル名を箇条書きで)

---
*`codex debug models` の出力より。実際に使えるモデルは認証種別（ChatGPT Plus / API キー）で異なる場合あり。*
```

**`--json` 指定の場合**:
````
## Codex CLI モデルカタログ (raw JSON)

```json
(取得した JSON)
```
````

4. 必要に応じて、`/ask-codex --model <name>` のような使い方の例を添える。
