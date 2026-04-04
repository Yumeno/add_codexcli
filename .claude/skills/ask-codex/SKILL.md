---
name: ask-codex
description: Codex CLI にセカンドオピニオンを求める。設計判断やバグ調査で別の視点が欲しい時に使う。
disable-model-invocation: true
allowed-tools: Bash Read
---

# /ask-codex — Codex CLI にセカンドオピニオンを求める

ユーザーの質問をそのまま Codex CLI に投げて、回答を取得して表示します。

## 手順

1. `$ARGUMENTS` をプロンプトとして使う。空の場合はユーザーに質問内容を聞く。

2. ラッパースクリプトのパスを特定する:
```bash
WRAPPER_DIR="${CLAUDE_SKILL_DIR}/../../../scripts"
```

3. OS を判定して適切なラッパーを呼び出す:

```bash
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    powershell -ExecutionPolicy Bypass -NoProfile -File "$WRAPPER_DIR/codex-wrapper.ps1" -Prompt "$ARGUMENTS"
else
    bash "$WRAPPER_DIR/codex-wrapper.sh" --prompt "$ARGUMENTS"
fi
```

> **注意:** ラッパー内部で `--` セパレータを使用しているため、`$ARGUMENTS` がダッシュで始まっても安全に処理される。

4. Codex の回答を表示し、以下の形式でユーザーに提示する:

```
## Codex CLI のセカンドオピニオン

> (ユーザーの質問)

(Codex の回答)

---
*Model: gpt-5.2-codex via Codex CLI*
```

5. 必要に応じて、Claude 自身の見解と比較してコメントを添える。
