---
name: list-codex-models
description: Codex CLI が認識しているモデル一覧を取得する。`--model` に渡せる値を確認したい時に使う。
disable-model-invocation: true
allowed-tools: Bash
---

# /list-codex-models — 利用可能なモデルを列挙する

`codex debug models` を呼び出して、Codex CLI が知っているモデル名を一覧表示します。
`/ask-codex` や `/ask-codex-with-context` で `-Model` (PS) / `--model` (bash) に何を渡せるか確認するためのスキル。

> **`disable-model-invocation` について:** デフォルトは `true`（手動起動のみ）。
> 自動呼び出しの必要性は低いので基本このままで OK。

## 引数の解釈

`$ARGUMENTS` は省略可能。以下のキーワードを含むと挙動が変わる:

- `bundled` / `オフライン` → `-Bundled` / `--bundled` を付ける（バイナリ同梱カタログのみ）
- `json` / `生` → `-Json` / `--json` を付ける（raw JSON 出力）
- それ以外 → 名前リスト（デフォルト）

## 手順

### 1. ヘルパースクリプトを呼び出す

> **重要 (許可プロンプト回避):** wrapper / helper を呼ぶときは
> **素の 1 コマンドで直接呼ぶこと。** 変数代入の前置やコマンド置換 (`OUTPUT=$(...)`) は
> 許可傘から外れて承認要求が出る。stdout はそのまま tool result に返るので捕捉不要。
> helper のパスは **必ず double quote で囲む**。

#### Windows + Claude Code (主用途)

オプションなし (名前リスト):
```bash
powershell -ExecutionPolicy Bypass -NoProfile -File "$HOME/.claude/scripts/list-codex-models.ps1"
```

オフライン (`-Bundled`):
```bash
powershell -ExecutionPolicy Bypass -NoProfile -File "$HOME/.claude/scripts/list-codex-models.ps1" -Bundled
```

raw JSON (`-Json`):
```bash
powershell -ExecutionPolicy Bypass -NoProfile -File "$HOME/.claude/scripts/list-codex-models.ps1" -Json
```

`-Bundled` と `-Json` の併用も可。引数の組み合わせは `$ARGUMENTS` のキーワードに応じて選ぶ。

#### Linux/Mac native 環境

```bash
bash "$HOME/.claude/scripts/list-codex-models.sh"
```

オプション: `--bundled` / `--json`。

### 2. 結果を以下の形式でユーザーに提示する

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

### 3. 必要に応じて、`/ask-codex -Model <name>` のような使い方の例を添える
