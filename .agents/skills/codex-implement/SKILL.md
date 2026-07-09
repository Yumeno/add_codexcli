---
name: codex-implement
description: Codex CLIを実装担当として明示的に起動し、cleanなGitリポジトリ内を最小権限で編集させて変更を独立検収する。ユーザーが「codex-implement」「Codexに実装させて」など実装委任を明示した場合に限って使う。
---

# Codex CLIへ実装を委任する

外部エージェントへ書き込み権限を渡す高リスク操作として扱う。ユーザーの明示指定なしに起動しない。

## 実行前チェック

1. 対象がGitリポジトリであることを確認する。
2. `git status --short` でclean treeを確認する。既存変更があれば停止し、勝手にstash、破棄、上書きしない。
3. この `SKILL.md` のディレクトリ直下の `scripts/` を絶対パスへ解決し、同梱された `codex-verify` の `snapshot` サブコマンドで実行前状態を記録する。`HEAD`、ブランチ、status、保護対象ファイル（`.env`、`.env.*`、`*.pem`、`*.key`、`*.p12`、`*.pfx`、`.git/config`、`.git/hooks`）のハッシュがスナップショットファイルへ記録される。成功時は最終行に `SNAPSHOT: <path>` が出る。この `<path>` を後の検収で使う。
4. リポジトリの絶対パスがASCIIのみであることを確認する。含む場合は停止し、ASCIIパスのworktreeへ移るよう案内する。
5. タスク、変更可能範囲、変更禁止範囲、受け入れ条件、実行すべきテストをUTF-8の一時仕様ファイルへ具体的に記述する。
6. コミット、push、PR作成、依存追加、破壊的操作を許可しない。dangerous flagや承認回避フラグは既定で禁止する。必要なら個別にユーザー承認を得る。

## 実行

同梱の `codex-wrapper` を、`SandboxMode workspace-write` と `-Cd` に対象リポジトリの絶対パスを渡して単独コマンドで呼ぶ。現在の作業ディレクトリや共通 `$HOME/scripts` を前提にしない。

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File "<解決したscripts>\codex-wrapper.ps1" -Prompt "タスク仕様書に従って実装してください" -ContextFile "C:/absolute/spec.txt" -Cd "C:/absolute/repo" -SandboxMode workspace-write -Timeout 600
```

```bash
bash "<解決したscripts>/codex-wrapper.sh" --prompt "タスク仕様書に従って実装してください" --context-file "/absolute/spec.txt" --cd "/absolute/repo" --sandbox workspace-write --timeout 600
```

`-SandboxMode workspace-write` は必須（既定の `read-only` ではCodexが編集できない）。権限拡大や対話承認の自動化を行わない。

## 独立検収

1. Codexの成功申告を根拠に完了扱いしない。
2. 実行前snapshotに対して `codex-verify` の `check` サブコマンドを実行する。`HEAD` / ブランチの一致、保護対象ファイルのハッシュ比較、`git status --porcelain=v1 --untracked-files=all` と `git diff HEAD --stat` のサマリがこの1コマンドで返る。

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File "<解決したscripts>\codex-verify.ps1" -Check -SnapshotFile "<snapshotパス>" -Repo "C:/absolute/repo"
```

```bash
bash "<解決したscripts>/codex-verify.sh" check --snapshot "<snapshotパス>" --repo "/absolute/repo"
```

3. check の出力で行頭 `[CODEX_VERIFY_VIOLATION]` があれば禁止操作（コミット・branch切替・保護対象改変等）が発生している。最優先で警告する。行頭 `[CODEX_VERIFY_ERROR]` は検収自体の失敗。`[CODEX_VERIFY_ALLOWED]` は事前承認済み変更のINFO。
4. Codexが応答末尾に列挙した変更ファイル一覧とcheckの実態を照合する。不一致なら明示的に警告する。
5. 依頼外変更、秘密情報、生成物、依存追加、危険なコマンド、テスト弱体化を検査する。
6. 既存環境で受け入れ条件に対応するテストを実行する。新しいテスト依存を勝手に追加しない。
7. 問題があれば、変更内容を保持したまま具体的に報告する。無断でresetやcheckoutを行わない。検収結果と検収結果に応じたロールバック手順（unstaged / staged / commit・branch切替の各分岐）をユーザーへ添える。
8. 自分が作成した一時仕様ファイルだけを、絶対パスと対象範囲を確認して削除する。

## 画像アセットの生成・編集

Codex CLIは画像生成を内包しており、このスキルのフローのまま画像の生成・編集を委任できる。仕様書を書く前に、この `SKILL.md` のディレクトリ直下の `references/image-generation.md` を読む。仕様書にはファイル名・形式・内容・スタイル・避けたい要素を書き、細かいプロンプトはCodexに任せる。編集は入力画像のリポジトリ内パスを書き、変更点の限定列挙と維持項目の明示列挙で指示する。生成モデル名は可視化されないため報告させない・推測で書かない。出力先はリポジトリ内に縛る。検収では生成物のmagic bytesを確認する。
