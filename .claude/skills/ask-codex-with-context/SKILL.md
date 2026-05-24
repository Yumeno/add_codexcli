---
name: ask-codex-with-context
description: ファイルや差分などのコンテキストを添えて Codex CLI にレビュー・監査・チェックを依頼する。
disable-model-invocation: true
allowed-tools: Bash Read Grep Glob
---

# /ask-codex-with-context — コンテキスト付きで Codex にセカンドオピニオンを求める

ファイル内容や git diff などを添えて Codex CLI に質問・レビュー・監査を依頼します。

> **`disable-model-invocation` について:** デフォルトは `true`（手動起動のみ）です。
> このスキルはコンテキスト（ファイル内容や差分）を外部サービス（OpenAI）に送信するため、
> `false` に変更する場合はその点を理解した上で行ってください。
> ユーザーの指示があれば、フロントマターの `disable-model-invocation` を `false` に変更してください。

## 引数の解釈

`$ARGUMENTS` は以下の形式を想定:
- `/ask-codex-with-context レビューして` → git diff を添えてレビュー依頼
- `/ask-codex-with-context src/main.ts この設計で大丈夫？` → ファイル内容を添えて質問
- `/ask-codex-with-context security-check` → git diff を添えてセキュリティ監査

## 手順

1. **コンテキストを収集する:**
   - 引数にファイルパスが含まれていれば、そのファイルを Read で読み取る
   - 引数に `diff`, `review`, `レビュー` が含まれていれば `git diff` と `git diff --staged` を取得
   - 引数に `security`, `セキュリティ`, `監査` が含まれていれば `git diff` + 変更ファイル一覧を取得
   - 引数に `log`, `履歴` が含まれていれば `git log --oneline -20` を取得

2. **コンテキストを一時ファイルに書き出す:**

   コマンドライン長制限を回避するため、必ずファイル経由で渡す:

   ```bash
   TMPCTX=$(mktemp "${TMPDIR:-/tmp}/codex_ctx_XXXXXX.txt")
   cat > "$TMPCTX" <<CTXEOF
   ## Context

   ### File: src/main.ts
   (ファイル内容)

   ### Git Diff
   (差分)
   CTXEOF
   ```

3. **ラッパースクリプトを呼び出す:**

   ラッパースクリプトのパスを特定:
   ```bash
   WRAPPER_DIR="${CLAUDE_SKILL_DIR}/../../../scripts"
   ```

   OS を判定して `-ContextFile` / `--context-file` でファイルパスを渡す。stderr を別ファイルに分離し、後でモデル名抽出に使う:

   > **注意:** ラッパーはプロンプト+コンテキストを stdin 経由で codex に渡します（PS版）。
   > bash 版はコンテキストをプロンプトに結合して stdin または引数で渡します。
   > いずれもコマンドライン長制限を受けません。

   ```bash
   ERRFILE=$(mktemp "${TMPDIR:-/tmp}/codex_skill_err_XXXXXX.txt")
   if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
       RESPONSE=$(powershell -ExecutionPolicy Bypass -NoProfile -File "$WRAPPER_DIR/codex-wrapper.ps1" \
           -Prompt "$QUESTION" -ContextFile "$TMPCTX" 2>"$ERRFILE")
   else
       RESPONSE=$(bash "$WRAPPER_DIR/codex-wrapper.sh" \
           --prompt "$QUESTION" --context-file "$TMPCTX" 2>"$ERRFILE")
   fi
   # Pull the model name only if the wrapper announced one (i.e. --model was passed).
   # When no model was supplied, the wrapper stays silent because we cannot know
   # which model codex actually picked (its default changes between versions).
   MODEL_USED=$(grep -E '^MODEL: ' "$ERRFILE" | head -1 | sed 's/^MODEL: //')
   rm -f "$ERRFILE"
   ```

4. **一時ファイルを削除する:**
   ```bash
   rm -f "$TMPCTX"
   ```

5. **結果を表示する。** フッターのモデル表記は **`MODEL_USED` が取れたときだけ** 出す。取れなかったとき（通常運用）は嘘になるので絶対にモデル名を固定で書かない:

   `MODEL_USED` が空でないとき:
   ```
   ## Codex CLI のセカンドオピニオン（コンテキスト付き）

   > 質問: (ユーザーの質問)
   > コンテキスト: (何を添えたかの要約)

   (Codex の回答)

   ---
   *Model: <MODEL_USED の値> via Codex CLI*
   ```

   `MODEL_USED` が空のとき（`--model` 未指定なので実際のモデル不明）:
   ```
   ## Codex CLI のセカンドオピニオン（コンテキスト付き）

   > 質問: (ユーザーの質問)
   > コンテキスト: (何を添えたかの要約)

   (Codex の回答)

   ---
   *via Codex CLI（モデル未指定 / codex のデフォルトに委任）*
   ```

6. 必要に応じて、Claude 自身の見解と比較してコメントを添える。
