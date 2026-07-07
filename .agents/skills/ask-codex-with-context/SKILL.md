---
name: ask-codex-with-context
description: テキスト、複数画像、git diff、git logなどのコンテキストを添えてCodex CLIにレビュー、監査、設計相談を依頼する。ユーザーがCodexによる画像確認や、ファイルパス・diff・security・監査と併せた質問を明示した場合に使う。
---

# コンテキスト付きでCodex CLIに質問する

送信対象をユーザーの依頼に必要な範囲へ限定する。秘密情報、認証情報、無関係なファイルを含めない。

## 手順

1. 対象を決める。
   - ファイルパス指定: そのファイルを読む。
   - `review` / `レビュー` / `diff`: `git diff` と `git diff --staged` を確認する。
   - `security` / `セキュリティ` / `監査` / `audit`: diffと変更ファイル一覧を確認する。
   - `log` / `履歴` / `history`: `git log --oneline -20` を確認する。
   - 画像指定: 指定された全ファイルをユーザーの順序どおり保持する。
2. 外部サービスへ送信すべきでない内容が見つかったら停止し、ユーザーへ対象除外または許可を求める。
3. 質問、対象の説明、必要な原文をUTF-8の一時ファイルへまとめる。正常ワークロードを黙って切り詰めない。大きすぎる場合は警告し、分割方針を示す。
4. この `SKILL.md` のディレクトリ直下の `scripts/` を絶対パスへ解決し、同梱されたwrapperを単独コマンドで実行する。現在の作業ディレクトリや共通 `$HOME/scripts` を前提にしない。

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File "<解決したscripts>\codex-wrapper.ps1" -Prompt "レビューしてください" -ContextFile "C:/absolute/path/context.txt"
```

複数画像の場合は、絶対pathを1行1件で並べたUTF-8ファイルを作り、`-AttachmentList`で渡す。単一画像だけなら`-Attachment`も使える。

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File "<解決したscripts>\codex-wrapper.ps1" -Prompt "順番に比較してください" -AttachmentList "C:/absolute/path/attachments.txt"
```

```bash
bash "<解決したscripts>/codex-wrapper.sh" --prompt "レビューしてください" --context-file "/tmp/context.txt"
```

```bash
bash "<解決したscripts>/codex-wrapper.sh" --prompt "順番に比較してください" --attachment "/path/first.png" --attachment "/path/second.jpg"
```

5. 失敗sentinelは回答と区別する。成功時はCodexの指摘と自身の検証結果を分けて提示する。
6. 作成した一時ファイルだけを、絶対パスと対象範囲を確認して削除する。

wrapperはCodex CLIの `-SandboxMode` を既定の `read-only` で呼ぶ。明示的にmodeを渡そうとしない。

wrapperが表示する順序、MIME、byte数、`probe-verified` を報告する。現在の対応形式はmagic bytesで確認したPNG/JPEGのみである。PDF、音声、動画、未知形式は拒否される。未認識形式を別形式へ暗黙変換しない。

このスキルは読み取りと質問用である。Codexへ編集を許可しない。実装委任には `codex-implement` を明示的に使う。
