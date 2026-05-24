---
name: ask-codex
description: Codex CLI にセカンドオピニオンを求める。設計判断やバグ調査で別の視点が欲しい時に使う。
disable-model-invocation: true
allowed-tools: Bash Read
---

# /ask-codex — Codex CLI にセカンドオピニオンを求める

ユーザーの質問をそのまま Codex CLI に投げて、回答を取得して表示します。

> **`disable-model-invocation` について:** デフォルトは `true`（手動起動のみ）です。
> `false` に変更すると「Codex にも聞いて」等の自然言語で Claude が自動的にこのスキルを呼べるようになります。
> ユーザーの指示があれば、フロントマターの `disable-model-invocation` を `false` に変更してください。

## 手順

1. `$ARGUMENTS` をプロンプトとして使う。空の場合はユーザーに質問内容を聞く。

2. ラッパースクリプトのパスを特定する:
```bash
WRAPPER_DIR="${CLAUDE_SKILL_DIR}/../../../scripts"
```

3. OS を判定して適切なラッパーを呼び出す。stderr を別ファイルに分離して取得し、後でモデル名抽出に使う:

> **注意:** ラッパーはプロンプトを stdin 経由で codex に渡すため、コマンドライン長の制限を受けません。
> また `--` セパレータにより、プロンプトがダッシュで始まっても安全です。

```bash
ERRFILE=$(mktemp "${TMPDIR:-/tmp}/codex_skill_err_XXXXXX.txt")
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    RESPONSE=$(powershell -ExecutionPolicy Bypass -NoProfile -File "$WRAPPER_DIR/codex-wrapper.ps1" -Prompt "$ARGUMENTS" 2>"$ERRFILE")
else
    RESPONSE=$(bash "$WRAPPER_DIR/codex-wrapper.sh" --prompt "$ARGUMENTS" 2>"$ERRFILE")
fi
# Pull the model name only if the wrapper announced one (i.e. --model was passed).
# When no model was supplied, the wrapper stays silent because we cannot know
# which model codex actually picked (its default changes between versions).
MODEL_USED=$(grep -E '^MODEL: ' "$ERRFILE" | head -1 | sed 's/^MODEL: //')
rm -f "$ERRFILE"
```

4. Codex の回答を表示する。フッターのモデル表記は **`MODEL_USED` が取れたときだけ** 出す。取れなかったとき（通常運用）は嘘になるので絶対にモデル名を固定で書かない:

`MODEL_USED` が空でないとき:
```
## Codex CLI のセカンドオピニオン

> (ユーザーの質問)

(Codex の回答)

---
*Model: <MODEL_USED の値> via Codex CLI*
```

`MODEL_USED` が空のとき（`--model` 未指定なので実際のモデル不明）:
```
## Codex CLI のセカンドオピニオン

> (ユーザーの質問)

(Codex の回答)

---
*via Codex CLI（モデル未指定 / codex のデフォルトに委任）*
```

5. 必要に応じて、Claude 自身の見解と比較してコメントを添える。
