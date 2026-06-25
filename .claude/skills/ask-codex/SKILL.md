---
name: ask-codex
description: Codex CLI にセカンドオピニオンを求める。設計判断やバグ調査で別の視点が欲しい時に使う。
disable-model-invocation: true
allowed-tools: Bash Read
---

# /ask-codex — Codex CLI にセカンドオピニオンを求める

ユーザーの質問をそのまま Codex CLI に投げて、回答を取得して表示します。
コンテキスト (ファイル / diff) を添えたい場合は `/ask-codex-with-context` を使ってください。

> **`disable-model-invocation` について:** デフォルトは `true`（手動起動のみ）です。
> `false` に変更すると「Codex にも聞いて」等の自然言語で Claude が自動的にこのスキルを呼べるようになります。
> ユーザーの指示があれば、フロントマターの `disable-model-invocation` を `false` に変更してください。

## 手順

### 1. `$ARGUMENTS` をプロンプトとして使う

空の場合はユーザーに質問内容を聞く。

### 2. ラッパースクリプトを呼び出す

> **重要 (許可プロンプト回避):** Claude Code の許可傘は
> ``Bash(powershell -ExecutionPolicy Bypass -NoProfile -File *codex-wrapper.ps1*)``。
> これは **コマンドが `powershell` で始まるときだけ** マッチする。
> 以下のシェル構文で包んだ瞬間に傘から外れて毎回承認要求が出る:
> - 変数代入の前置: `ERRFILE=... powershell ...`
> - コマンド置換: `RESPONSE=$(powershell ...)`
> - stderr リダイレクト: `powershell ... 2>file`
> - パイプ: `powershell ... | tee log`
>
> **素の 1 コマンドで直接呼ぶこと。** stdout はそのまま tool result に返るので捕捉不要。
> wrapper パスは **必ず double quote で囲む** (quote なしも傘から外れる)。

#### Windows + Claude Code (主用途)

グローバルインストール想定 (`~/.claude/scripts/codex-wrapper.ps1`):

```bash
powershell -ExecutionPolicy Bypass -NoProfile -File "$HOME/.claude/scripts/codex-wrapper.ps1" -Prompt "質問文"
```

プロンプトに長い文を渡す場合も、ラッパーが stdin 経由で codex に渡すためコマンドライン長制限は気にしなくてよい。
プロンプトがダッシュで始まっても `--` セパレータで安全に扱われる。

#### Linux/Mac native 環境

```bash
bash "$HOME/.claude/scripts/codex-wrapper.sh" --prompt "質問文"
```

### 3. Codex の回答を表示する

#### 失敗検知 (重要)

wrapper が失敗したとき、**stdout の先頭に `[CODEX_WRAPPER_ERROR]` で始まる行が出る**。
これは「素の 1 コマンド呼び」で stdout/stderr を分離しない運用でも、Claude が
「これは Codex の回答ではなく wrapper の失敗だ」と確実に判別できるようにするための sentinel。

tool result の中に `[CODEX_WRAPPER_ERROR]` が含まれていたら、**Codex の回答ではなく
wrapper のエラーとして提示する**。例:

```
## Codex CLI 呼び出しに失敗しました

(sentinel 行とそれ以降のエラー詳細をそのまま掲示)
```

成功時は sentinel が出ないので、以下の通常フォーマットを使う。

#### 通常のフォーマット (成功時)

stderr を分離しない運用ではモデル名は取得できないので、フッターは常に以下の「モデル未指定」形式を使う。
**固定のモデル名を書くのは嘘になるため絶対にしない。**
`-Model` を明示的に渡した場合のみ、その値を使ってよい。

#### 通常運用（`-Model` 未指定）

```
## Codex CLI のセカンドオピニオン

> (ユーザーの質問)

(Codex の回答)

---
*via Codex CLI（モデル未指定 / codex のデフォルトに委任）*
```

#### `-Model gpt-5.5` のように明示した場合

```
---
*Model: gpt-5.5 via Codex CLI*
```

### 4. 必要に応じて、Claude 自身の見解と比較してコメントを添える
