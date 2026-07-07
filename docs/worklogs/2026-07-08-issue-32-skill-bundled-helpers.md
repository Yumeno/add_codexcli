# Issue #32: Skill bundled helpers refactor (Phase 1-4)

## 背景

姉妹リポジトリ (add_claudecode, add_antigravitycli) の議論を経て、Skill 内 `scripts/` へ
helper を同梱する配布方式が採用された。add_codexcli もこれに倣う refactor を実施する。

**元の問題**:
- `.claude/skills/` と `.agents/skills/` 双方の SKILL.md が絶対パス (`$HOME/.claude/scripts/`) や
  プレースホルダ (`{{SCRIPTS_ROOT}}`) で共通 scripts ディレクトリを参照していた
- installer が helper 6 個を独立配布し、SKILL.md 側でも path 置換を行う複雑な二段構造
- 移植 (installer 経由) と手動運用 (方法 1〜3) で異なる path 前提を持ち、
  プロジェクトローカル運用時に SKILL.md の手動編集が必要な P1 課題があった (issue #27)

**目的**:
- Skill 単位の自己完結: 各 Skill が自身の `scripts/` サブディレクトリで helper を保持
- SSoT (`scripts/`) と Skill 同梱 (`.{claude,agents}/skills/*/scripts/`) の分離、同期tool経由
- installer を「Skill を丸ごとコピー」まで簡素化、path 置換ロジック廃止
- Claude Code 用 installer を新規追加 (issue #27 の合流)

## 全体アーキテクチャ

```
scripts/                         # SSoT (helper 6 個の正本)
    codex-wrapper.{sh,ps1}
    codex-verify.{sh,ps1}
    list-codex-models.{sh,ps1}

tools/
    sync-skill-scripts.{sh,ps1}  # 正本 → 各 Skill 同梱への配布 / 検証tool

.claude/skills/<name>/scripts/   # Claude Code 用 Skill 同梱 (正本の複製)
.agents/skills/<name>/scripts/   # Antigravity CLI 用 Skill 同梱 (同じく複製)

$HOME/.agents/add_codexcli/      # モデル設定 (ホスト間共有)
    codex-wrapper.conf
```

**Skill 名と同梱 helper の対応**:

| Skill | 同梱 helper |
|---|---|
| `ask-codex` | `codex-wrapper.{sh,ps1}` |
| `ask-codex-with-context` | `codex-wrapper.{sh,ps1}` |
| `codex-implement` | `codex-wrapper.{sh,ps1}` + `codex-verify.{sh,ps1}` |
| `list-codex-models` | `codex-wrapper.{sh,ps1}` + `list-codex-models.{sh,ps1}` |
| `set-codex-model` | `codex-wrapper.{sh,ps1}` |

## Phase 分割の方針

一括 PR ではなくフェーズ分割 (案 B) を採用。理由:
- 変更範囲が広く (10 SKILL.md + wrapper + installer + tests)、レビュー粒度を保つため
- 各段階で `test-skill-bundles` の状態が明確 (Phase 1: FAIL 期待、Phase 2a 以降: PASS)
- 万一の不具合切り分けを容易にする

| Phase | PR | 内容 |
|---|---|---|
| 1 | #33 | `tools/sync-skill-scripts` + `test-skill-bundles` の追加 (bundle 未生成、テストは FAIL 期待) |
| 2a | #34 | 10 bundle 生成 (テスト PASS へ遷移、SKILL.md は未変更で inert) |
| 2b | #35 | wrapper の config path を bundle 共有位置に切り替え、test-wrapper 系を CODEX_WRAPPER_CONFIG 経由の一時 path 前提に改修 |
| 2c | #36 | 10 SKILL.md の helper 参照を `$SKILL_DIR/scripts/` に統一 |
| 3 | #37 | installer 簡素化 + `install-for-claude-code` 新規追加 (issue #27 close) |
| 4 | (本 PR) | README 全面書き直し + 旧配置からの移行ガイド + 本 worklog |

## Phase ごとの検証結果

### Phase 1 (PR #33)

`tools/sync-skill-scripts.{sh,ps1}` は distribute mode と `--check` mode を持つ対称実装。
姉妹リポの実装を本リポ用にローカライズ (skill 名・helper 名だけ差し替え)。

- 配布モード: `.<host>/skills/<name>/scripts/` を作成 → delete-then-copy で許可 helper のみ配置
- `--check` モード: 各 bundle が正本と byte 単位で一致し、期待外のファイルが無いことを検証
- sentinel: 配布失敗時のみ `[SYNC_SKILL_SCRIPTS_ERROR]`。mismatch は通常の diagnostic

テスト遷移:
- Phase 1 コミット時点: `test-skill-bundles` は "scripts directory missing" × 10 で **FAIL** (期待通り)
- Phase 2a 以降: PASS へ遷移

### Phase 2a (PR #34)

`bash tools/sync-skill-scripts.sh` を実行して 28 ファイル (5 Skill × 2 ホスト × helper セット) を
配布。既存 SKILL.md は未変更のため、bundle は inert (どこからも参照されない状態)。

- `test-skill-bundles.{sh,ps1}`: PASS に遷移
- `test-wrapper.ps1`: 49/49 PASS (回帰確認、1 件初回 flake は real codex 依存で再現せず)

### Phase 2b (PR #35)

wrapper の config path を `SCRIPT_DIR/codex-wrapper.conf` から
`$HOME/.agents/add_codexcli/codex-wrapper.conf` に変更 (`CODEX_WRAPPER_CONFIG` 環境変数で上書き可)。
姉妹リポ準拠のシンプルな config フォーマット (heredoc → 1 行 printf)。

test-wrapper 系は `CODEX_WRAPPER_CONFIG` に一時 path を強制指定する形に改修。
既存の backup/restore ロジックは一時 path なので不要となり削除。

**発生した事故 (Codex sandbox ACL)**:
- `.agents/skills/ask-codex/scripts/` に Codex sandbox の SID に対する Deny ACL があり、
  sync-skill-scripts の delete-then-copy 中に 2 ファイルが欠落
- 私 (Claude Code) の権限で sync 再実行して完全復旧、リポには影響なし
- Phase 2c と 3 でも同じ SID Deny ACL が影響する可能性があるので、Phase 2c で
  `.agents/skills/` を触る際は同じ現象が再発する前提で運用

テスト:
- `test-wrapper.sh`: 54/54 PASS
- `test-wrapper.ps1`: 49/49 PASS (2 回連続確認)
- `test-skill-bundles.{sh,ps1}`: PASS

### Phase 2c (PR #36)

10 SKILL.md の helper 参照を `$HOME/.claude/scripts/...` / `{{SCRIPTS_ROOT}}` から
`<scripts-root>` (skill 実行時に LLM が SKILL.md 自身のディレクトリ直下の `scripts/` を
絶対 path 解決) に統一。

- `.claude/skills/` 5 個: 既存の許可傘運用ノウハウ、TEMP 命名規約、sentinel 検知、
  フッター形式などは全て維持し、helper path のみ差し替え
- `.agents/skills/` 5 個: 姉妹リポ準拠で全面リライト。frontmatter は minimal
  (`name` + `description` のみ)、本文は「この SKILL.md のディレクトリ直下の `scripts/` を
  絶対パスへ解決」する形式に統一

**再発した Codex sandbox ACL 問題**:
- Phase 2b で予測した通り `.agents/skills/` 全体で書き込み拒否発生
- Codex は `.claude/skills/` 5 個のみ完了、`.agents/skills/` は私が姉妹準拠で補完

Codex 版と本リポ版の主な差分 (`.agents/skills/`):
- `antigravity-wrapper` → `codex-wrapper`
- Antigravity の boolean `--sandbox` → Codex の `-SandboxMode <mode>`
- MIME 対応形式: PNG/JPEG のみ (Antigravity は音声・動画・PDF も対応)
- `agy models` → `codex debug models`

テスト:
- `test-wrapper.{sh,ps1}`: 全 PASS 維持
- `test-skill-bundles.{sh,ps1}`: PASS
- 旧 path 残存 grep: 0 件

### Phase 3 (PR #37, #27 close)

installer を新設計に合わせて簡素化 + Claude Code 用 installer 新規追加。

**Antigravity installer 書き直し**:
- `scripts_root` 引数 (第 2 引数) を削除 (helper 独立配布廃止)
- `{{SCRIPTS_ROOT}}` sed 置換とその escape 処理を削除
- helper 6 個の独立コピーループを削除
- `cp -R` / `Copy-Item -Recurse` で Skill ディレクトリ全体を再帰コピー
- 既存の Fix D retire-then-promote (`.new` / `.old` rollback) は維持 (本リポの資産)

**Claude Code installer 新規**:
- Antigravity 版と完全対称 (source と destination のみ差分)
- source: `.claude/skills/`
- destination default: `$HOME/.claude` (その下の `skills/` に配置)

**テスト調整・新規**:
- `test-install-antigravity.{sh,ps1}`: scripts_root 引数削除、helper 同梱 assertion 追加
- `test-install-claude-code.{sh,ps1}` を新規追加、Antigravity テストと対称構造
- Windows で `chmod 555` の read-only enforcement が効かないため、Fix D の rollback
  read-only テストは SKIP 扱い (既存パターン踏襲)

テスト:
- `test-install-antigravity.{sh,ps1}`: PASS (bash 1 SKIP、ps 10/10 PASS)
- `test-install-claude-code.{sh,ps1}`: PASS (bash 1 SKIP、ps 10/10 PASS)

### Phase 4 (本 PR)

README を新設計に合わせて全面書き直し + 旧配置からの移行ガイド追加。

- 「対応ホスト」表を helper 同梱前提に整理
- Claude Code インストール手順を `install-for-claude-code.{sh,ps1}` に切り替え (旧「方法 1/2/3」を削除)
- Antigravity インストール手順から `scripts_root` 引数関連を削除
- 「旧配置からの移行」セクション新規追加: `~/.claude/scripts/` と `~/.gemini/scripts/` の手動削除案内、
  `codex-wrapper.conf` の新配置への移し方
- 「/set-codex-model」の config file 場所説明を新 default path に更新
- 「ファイル構成」を Skill 同梱構造 + tools/ 追加を反映して書き直し
- 「テスト」に `test-install-claude-code` と `test-skill-bundles` を追加、
  helper 直接編集禁止の注意書きを追加

## Codex 委任時に判明した知見

### Codex sandbox の SID 依存 Deny ACL

Codex CLI の sandbox が `.agents/skills/<name>/scripts/` に対して sandbox SID を持つ user への
Deny ACL を付けることがあり、`workspace-write` 指定でも書き込みできない。Claude Code 側から
再実行すれば書き込める。

**Phase 2b の一時被害**: sync-skill-scripts が delete-then-copy 方式のため、Deny ACL のディレクトリで
先に delete が実行されて 2 ファイルが欠落する状態が発生した。

**回避策**: `.agents/skills/` を触る Codex 委任では以下いずれか:
1. 事前に Claude Code 側で対象ディレクトリの ACL を修正 (今回未実施)
2. Codex 完了後、私が sync-skill-scripts を再実行して補完 (Phase 2b で採用)
3. `.agents/skills/` 系の変更を Claude Code 側で行う (Phase 2c で採用)

将来的には issue #21 の hardening リストに追加検討。

### Codex sandbox の PATH に `codex` が居ないケース

Phase 2b / 2c で Codex 委任時のテスト実行で「real codex 依存の 3〜4 件が FAIL」と報告された。
host 環境では全 PASS であり、Codex sandbox 環境固有の PATH 問題と判明。

**判定基準**: Codex 委任時のテスト結果は参考程度、必ず host 環境で独立実行して判定する。

### 姉妹リポの参照方法

`gh api repos/<owner>/<repo>/contents/<path> -q '.content' | base64 -d` で main branch の
任意ファイルを取得できる。仕様書に姉妹の path を書いておくと Codex が能動的に参照する。

## 未対応 (別 issue で追跡)

- **#29**: bash installer の `set -e` による rollback 診断消失 (P3、Fix D の詳細エラー掌握困難)
- **#30**: Windows での rollback / Ctrl-C 保護未検証 (P3、`chmod 555` が Windows で無効)
- **#31**: 一部テスト assertion label の説明改善 (P3)
- **#21 に追加検討**: Codex sandbox ACL 問題への対処

## 統計

| 項目 | 数 |
|---|---|
| PR 数 | 5 (#33, #34, #35, #36, #37) + 本 PR |
| close された既存 issue | #27 (Claude Code installer) |
| 追加ファイル | 8 (tools 2 + test-install-claude-code 2 + install-for-claude-code 2 + bundles 大量) |
| 変更ファイル (単発 diff で) | 最大 28 (Phase 2b で全 wrapper 更新) |
| Codex 委任回数 | 4 (Phase 1, 2b, 2c, 3) |
| Codex 委任成功率 | 3/4 完全成功、1/4 部分成功 (Phase 2c、`.agents/skills/` は Claude Code 補完) |

## 参照

- 姉妹リポ (先行実装): [add_claudecode](https://github.com/Yumeno/add_claudecode)、
  [add_antigravitycli](https://github.com/Yumeno/add_antigravitycli)
- 親 issue: [#32](https://github.com/Yumeno/add_codexcli/issues/32)
- close された issue: [#27](https://github.com/Yumeno/add_codexcli/issues/27)
- 併走で追跡する P3 issue: #29, #30, #31
