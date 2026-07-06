# PR #26: Issue #24 / #25 のレビュー由来 P2 修正 4 件

- 作業日: 2026-07-07
- 対象 PR: [#26 Fix P2 issues in #24 (image attachments) and #25 (Antigravity installer)](https://github.com/Yumeno/add_codexcli/pull/26)
- 対象 Issue: [#24 複数画像 attachment](https://github.com/Yumeno/add_codexcli/issues/24) / [#25 Antigravity CLI 対応](https://github.com/Yumeno/add_codexcli/issues/25)
- 状態: マージ済み、Claude Code / Antigravity CLI の両ホストにグローバル install 済み

## 目的

`main` に既に入っていた issue #24 (画像 attachment) / #25 (Antigravity installer) の実装に対して独立コードレビューを行い、検出された P2 を修正する。同時に、レビュー方法論そのものの教訓を運用ガードに反映する。

## レビュー体制

- 一次レビュー: Opus 4.7 独立
- セカンドオピニオン: Codex CLI (`/ask-codex-with-context` 経由)
- 実装委任: Codex CLI (`/codex-implement` 経由、`codex-verify` snapshot/check 付き)
- 再監査: Codex CLI (2 ラウンド) + Opus post-fix independent review
- 環境: Windows 11 + Git Bash 5.2.37 + PowerShell 5.1

このセッションでは PR #23 のレビュー時に issue #21 で定めた「Codex + Opus 二段構え」の運用ガードを 2 度目の適用として実行した。

## 検出と分類

### 初回 Opus レビュー (6 P2 候補)

Windows 環境で `main` の変更を独立にコードリーディングし、以下を検出:

- #25 P2-1: PS installer の `$windowsRoot` dead code + path separator 不一致
- #25 P2-2: bash installer の `sed` エスケープ不完全
- #25 P2-3: staging directory の `.` prefix + scanner race
- #24 P2-1: PS Ctrl-C cleanup 漏れ
- #24 P2-2: bash control-char 検知の 3-process pipeline
- #24 P2-3: bash manifest.json JSON escape 不完全

### Codex セカンドオピニオン結果

Codex に上記の妥当性検証を依頼した結果:

| 指摘 | Codex 判定 | 深刻度調整 |
|---|---|---|
| #25 dead code + separator 不一致 | P3 に格下げ (実害未証明) | P3 |
| #25 sed エスケープ不完全 | P3 に格下げ (通常 Unix path で十分) | P3 |
| #25 staging race | P3 以下 (installer 間 race の方が重要) | P3 |
| #24 PS Ctrl-C cleanup | P2/P3 境界 (試みは正当) | P2 (Fix C) |
| #24 control-char pipeline | 撤回推奨 (`[[:cntrl:]]` は locale 依存) | 撤回 |
| #24 JSON escape | 偽陽性 (制御文字は事前検知で到達不能) | 撤回 |

さらに Codex は Opus が見落としていた 3 件を追加検出:

- **#24: bash attachment-list の CRLF / UTF-8 BOM 非対応** — Fix A
- **#24: magic-byte 検査とコピー間の TOCTOU** — Fix B
- **#25: installer 更新が非原子的 (`rm→mv` 失敗で消失可能)** — Fix D

## 実装 (Codex 委任)

`/codex-implement` フローで Codex CLI に修正 4 件 + dead code 削除を委任。仕様書は約 250 行で以下を明示:

- 各 Fix の問題、期待される修正、テスト追加項目
- 変更対象ファイルの限定 (8 ファイル)
- スタイル (`set -euo pipefail`, PS 5.1 互換 + UTF-8 BOM)
- 完了報告フォーマット

委任前に `codex-verify snapshot`、委任後に `codex-verify check` で HEAD/branch/保護対象の非改変を確認。VIOLATION 行なしを確認して受領。

### 実装された修正

- **Fix A** (bash): `--attachment-list` に CRLF 除去、初行 BOM 除去、空白のみ行除外を追加
- **Fix B** (両版): magic-byte / size 検査を staged copy に対して行うよう順序変更。元 path の symlink/regular file 検査は残す
- **Fix C** (PS): wrapper 主本体を `try { ... } finally { Cleanup }` で囲む
- **Fix D** (両 installer): `rm→mv` の代わりに `.new`/`.old` を経由した retire-then-promote 方式。failure 時は `.old` を復元。再実行で残骸を吸収
- **Fix E** (PS installer): `$windowsRoot` dead code を 1 行削除

### 追加テスト

- bash test-wrapper.sh: 4 ケース追加 (CRLF+BOM、LF only、空白行、staged copy 独立性)
- ps1 test-wrapper.ps1: 対称 4 ケース + timeout cleanup
- bash test-install-antigravity.sh: read-only rollback、残骸吸収、`.new`/`.old` 掃除の 3 追加検査
- ps1 test-install-antigravity.ps1: 残骸吸収と `.new`/`.old` 掃除の 2 ケース追加

テスト結果 (独立再実行):

- test-wrapper.sh: 54/54 PASS
- test-wrapper.ps1: 49/49 PASS
- test-media-wrapper.ps1: 1/1 PASS
- test-install-antigravity.sh: PASS (read-only は Windows で SKIP)
- test-install-antigravity.ps1: 9/9 PASS

## 監査経過

| ラウンド | 実施 | 結果 |
|---|---|---|
| 1 | Codex round-1 audit | P1/P2 なし判定、リリース可能 |
| 2 | Opus post-fix independent review | 1 P2 (sed replacement バグ) を検出したと主張、P3 4 件 |
| 3 | Codex 再検証 (Opus の主張を) | Opus の観測は methodology 誤り、二重化は正しく機能 |
| 4 | Opus methodology 検証 (ファイル経由で sed 実測) | Codex が正しかったことを確認、P2 主張を撤回 |

最終: P1/P2 ともに 0。P3 のみ 4 件が follow-up 対象として issue #24 / #25 に追記された。

## 撤回された P2 主張の記録

Opus が「install-for-antigravity.sh の sed replacement で Windows パス `\U` などが特殊解釈される」と主張し、その後撤回した。撤回の経緯:

1. Opus が Bash tool の inline command で `printf '%q'` の出力を見て「二重化されていない」と誤読
2. `printf '%s' | od -An -c` に切り替えて再測定、依然として「二重化されていない」ように見えた
3. Codex に確認、Codex は同じ Git Bash 5.2.37 で **実測して二重化を確認**、Opus の観測方法を疑うよう指摘
4. Opus が bash script をファイルに書き出して実行したところ **二重化は正しく機能** していた
5. 原因: Claude Code の Bash tool inline 入力経路で `\\\\` が `\\` に減っていた (msys シェル層での escape 消費)

結論: `${scripts_root//\\/\\\\}` は Git Bash 5.2.37 で正しく機能する。sed への replacement には二重化された `\\` が届き、sed の `\U` メタ sequence は発火しない。**install-for-antigravity.sh のエスケープは正しい**。

## 検証結果

### 通信あり (実 codex CLI)

- Claude Code 側 (`~/.claude/scripts/codex-wrapper.ps1`) から `-ShowModel` / 空 `-Prompt` (sentinel 経路) / 存在しない attachment (sentinel + cleanup) の 3 パターン smoke 確認
- 実 attachment 送信は今回スコープ外 (issue #24 のマージ前セッションで実施済み、変更点は主に境界条件)

### 通信なし (テスト)

前述の 5 test suite 全 PASS。

### Antigravity CLI 実機

前セッションで確認済み (worklog `2026-07-06-issue-25-antigravity-cli.md` 参照)。今回はスキル定義変更なし、wrapper のバグ修正のみのため実機再確認は省略。

## Global install

セッション最後に両ホストへ更新配布:

### Claude Code (`~/.claude/`)

- scripts バックアップ: `codex-wrapper.{sh,ps1}.bak.20260707`
- 更新: `codex-wrapper.sh` / `codex-wrapper.ps1` のみ
- smoke: `-ShowModel` / `-Prompt` 不足 sentinel / 存在しない attachment sentinel が正常動作

### Antigravity CLI (`~/.gemini/`)

- skills バックアップ: `antigravity-cli/skills.bak.20260707/`
- scripts バックアップ: `scripts/*.bak.20260707-antigravity`
- インストーラー: `scripts/install-for-antigravity.ps1` (Fix D 経由の retire-then-promote)
- 結果: 5 skill (`ask-codex`, `ask-codex-with-context`, `codex-implement`, `list-codex-models`, `set-codex-model`) 全て更新、`.new`/`.old` 残骸 0 件、`{{SCRIPTS_ROOT}}` プレースホルダも正しく置換

## 得られた運用教訓

PR body および issue #24 / #25 のコメントに反映済み。今後の運用ガードに追加する項目:

- **観測結果を確定情報と誤認する癖** に注意する。テスト緑を網羅と誤認する癖 (issue #21) の反対側にある同じ構造の失敗モード
- **Bash tool の inline command と file-based script は escape 挙動が異なる**。escape に敏感な検証は必ずファイルに書いて実行する
- **`printf '%q'` は shell-quoted 表示であって byte view ではない**。byte view には `printf '%s' | od -An -tx1` を使う
- **peer reviewer の独立実測と自分の観測が食い違ったら、まず自分の methodology を疑う**。今回は Codex が同じ Git Bash 5.2.37 で二重化を実測している時点で、Opus 側の疑いを深めるべきだった

Codex + Opus 二段構えの意義は「片方の誤りをもう片方が検出できる」ことにあり、今回は Opus 側の誤検出を Codex 側が正しく否定するケースで初めて機能した。

## 残課題

以下は follow-up として issue #24 / #25 に記録済み。今 PR には含めない:

### issue #24 側 (P3)

- attachment のサイズ / 総数上限がない
- PS `C:\tmp` fallback の ACL / reparse-point 未検証
- `-Attachment` + `-AttachmentList` の順序契約が SKILL.md 未明示
- JPEG magic-byte 4 byte 目未検査
- 非 UTF-8 filename と manifest.json の挙動
- PS Ctrl-C 保護は PS 5.1 の制約で完全ではない
- "Staged attachment remains valid" test の assertion ラベリング

### issue #25 側 (P3)

- PS installer の path separator 統一 (dead code 削除の続き)
- staging directory の `.` prefix / scanner race
- Fix D の rollback path が Windows で誰も検証していない
- `set -e` により rollback 診断メッセージが失われ得る

## 追記: README のインストール手順の構造修正

同セッション内でユーザーから「README から Claude Code へのインストール方法がなくなっている気がする」と指摘があり、調査したところ **文言は残っていたが見出し構造が壊れていた** ことが判明。

### 原因

`1c5f95d` (Antigravity CLI 対応の追加コミット) で `## インストール` セクションに `### Antigravity CLI へインストール` を追加した際、既存の Claude Code 向けセクションの親見出し (`### Claude Code へインストール`) を作らなかった。結果、既存の `### 方法 1..4` (Claude Code 向け) が Antigravity セクションと **同じ h3 レベル** で並列に見える構造になり、読み手からは「Antigravity のインストールに続く更なる方法」として認識される状態になっていた。

削除は起きていない (README.md の commit 履歴で単調増加を確認)。純粋に見出し階層の設計ミス。

### 修正内容

- `### Claude Code へインストール` を新規追加 (親見出し、Antigravity セクションと対称)
- `### 方法 1..4` を `#### 方法 1..3` に降格 (4 番だった「グローバルインストール」を推奨として 2 番に繰り上げ、方法 2..3 の統合を整理)
- 内容を **現行の 5 skill / 6 scripts に更新** (以前は `ask-codex` と `ask-codex-with-context` の 2 個のみ記載されていた)
- SKILL.md の path 参照仕様が `$HOME/.claude/scripts/` 直接記述になっている (issue #17 で刷新済み) ことを反映
- プロジェクトローカル運用時に SKILL.md の path を手動書き換えが必要な制約を明記
- 古い注記 (`${CLAUDE_SKILL_DIR}/../../../scripts/` 参照など) を削除

## 追加: Claude Code 向けインストーラーの issue

上記のプロジェクトローカル運用の不便 (`SKILL.md` を手動で書き換える必要) を解消するため、Antigravity 版 (`install-for-antigravity.{sh,ps1}`) と対称の Claude Code 向けインストーラーを新規 issue として登録:

- [#27 [enhancement] Claude Code 向けインストーラー (install-for-claude-code.{sh,ps1}) を用意する](https://github.com/Yumeno/add_codexcli/issues/27)

要件は Antigravity 版と同じ (retire-then-promote、allowlist、残骸吸収、テスト対称)。実装は別 PR で行う。

## 参照資料

- PR: [#26 Fix P2 issues in #24 (image attachments) and #25 (Antigravity installer)](https://github.com/Yumeno/add_codexcli/pull/26)
- 前提となる運用ガード: [issue #21 codex-verify hardening](https://github.com/Yumeno/add_codexcli/issues/21)
- 新規: [#27 Claude Code 向けインストーラー](https://github.com/Yumeno/add_codexcli/issues/27)
- 前セッション worklog: [2026-07-06 Issue #24 複数画像 attachment](2026-07-06-issue-24-multiple-images.md), [2026-07-06 Issue #25 Antigravity CLI 対応](2026-07-06-issue-25-antigravity-cli.md)
