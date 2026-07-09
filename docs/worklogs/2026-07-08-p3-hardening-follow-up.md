# P3 hardening follow-up (issue #29, #30, #31, plus CI issue #40)

## 背景

issue #32 (skill bundled helpers refactor) が完了した後、PR #26 の Opus post-fix review で
検出されていた P3 hardening 3 件をまとめて処理する follow-up セッション。作業は 2026-07-08
から 2026-07-09 にかけて実施。

対象:
- #25 (Antigravity CLI Skill install 追加、実装は既に完了、書類上の close のみ)
- #29 (installer bash 版 `set -e` で rollback 診断が消える)
- #30 (Windows 環境固有の未検証パス 2 件: rollback 検証 + Ctrl-C 保護)
- #31 (test-wrapper.ps1 の test-case 名が実態と乖離)
- #40 (Linux CI 自動化、新規起票)

進め方の合意:
- 軽い変更は 1 PR にまとめる (#29 + #31 → PR #39)
- Windows rollback path 検証 (test only) と Ctrl-C 保護 (wrapper 本体) は独立 PR に分ける
- CI 化は別 issue に切って本セッションでは着手しない

## 処理内容

### issue #25 → close (実装済み確認)

Antigravity CLI 向け Skill install は PR #26 で初回実装、PR #37 (issue #32 Phase 3) で
新設計 (helper 同梱、単一引数) に刷新済み。書類上 open のままだったので close コメントで
経緯を記録して close。

### issue #29 + #31 → PR #39 (quick win)

#### #29 の内容
`scripts/install-for-{antigravity,claude-code}.sh` の rollback ブロック:

```bash
if ! mv -- "$new_dest" "$final_dest"; then
    [[ ! -e "$old_dest" ]] || mv -- "$old_dest" "$final_dest"  # ← set -e で落ちると
    printf 'Failed to promote new skill: %s\n' "$name" >&2     # ← ここに到達しない
    exit 1
fi
```

`set -euo pipefail` によって rollback の `mv` 失敗時に主診断メッセージが失われる。
PR #37 で installer を書き換えたが、Antigravity と Claude Code の両版が同じロジックを
継承しているため、両ファイルへの修正が必要になった。

#### #29 の修正
2 段の `if !` guard に書き換え。rollback 失敗時は独自の診断行 (leftover path 付き) を
先に出し、その後で主診断行を必ず出力する構造:

```bash
if ! mv -- "$new_dest" "$final_dest"; then
    if [[ -e "$old_dest" ]]; then
        if ! mv -- "$old_dest" "$final_dest" 2>/dev/null; then
            printf 'Rollback also failed for %s (leftover: %s)\n' "$name" "$old_dest" >&2
        fi
    fi
    printf 'Failed to promote new skill: %s\n' "$name" >&2
    exit 1
fi
```

`|| true` 案より診断性が高い (rollback 失敗そのものを識別できる)。rollback 側の
`mv` の stderr は `2>/dev/null` で捨てる (raw error は downstream noise、独自診断の方が
オペレーターに読める)。

#### #29 のテスト追加
`test-install-{antigravity,claude-code}.sh` の read-only rollback ケースを拡張。
現状は exit code と prior content の生存だけを見ていたが、`Failed to promote new skill:`
が stderr に出ることを `grep -Fq` で assert。

**Windows での SKIP**: 既存の `chmod 555` probe が Windows で bypass されるため、rollback
codepath 自体が発火しない → 追加した grep assertion も同じ SKIP guard の下に隠れる。
これは既存パターン踏襲。実行担保は Linux 環境 (CI) が入るまでは wsl 手動実行や
manual review に依存。

#### #31 の内容
`scripts/tests/test-wrapper.ps1` の

```powershell
Test-Case "Staged attachment remains valid after source is removed" {
```

名前は TOCTOU 保護の検証を示唆するが、実際は `Stage-Attachments` 完了 **後** に source
を削除するタイミングで、単に「staged copy が source の lifecycle から独立している」ことを
確認しているだけ。名前の誤読を将来のメンテナーが起こすリスクがある。

#### #31 の修正
テスト本体は妥当な検証なので改名のみ:

```powershell
Test-Case "Staged attachment is independent of source file lifecycle" {
```

真の TOCTOU テスト (`Stage-Attachments` 実行中の source 差し替え) は production コードに
test-only hook が必要で規模が違う。別 issue 案件として残す。

**Result**: PR #39 マージ、#29 と #31 が close。

### issue #30 Part 1 → PR #41 (Windows rollback path 検証)

#### 問題
`test-install-{antigravity,claude-code}.ps1` に read-only rollback テストの
placeholder (`skips read-only rollback on Windows` として `Write-Host "SKIP ..."` するだけ)
があり、Windows での rollback path が誰にも検証されていない。bash 版の `chmod 555` は
Windows で bypass されるため、rollback 経路が Linux でしか実測されていない状態。

#### 修正
`Set-Acl` で現在ユーザーに Write Deny ACE を追加する fixture を実装。手順:

1. sentinel file (`previous.txt`) を既存 `ask-codex` skill に置く
2. `skills\` の元 ACL を保存
3. Write Deny ACE を追加
4. probe write で enforcement が効いているか確認 (Administrator + SeRestorePrivilege 環境では
   Deny を bypass する) — 効かなければ既存 SKIP パターンを踏襲して SKIP
5. installer を実行、`exit != 0` を assert
6. `finally` で ACL を必ず復元 (テスト後の cleanup を可能にするため)
7. sentinel file の生存を assert (prior content が保護されたことを外部から観察可能な形で確認)

#### 実装のポイント
- テスト名を最終的に「preserves prior content on failure」にした。理由: installer の
  内部で「rollback path (line 41 catch)」と「rename が始まっていない (line 38 で失敗)」の
  どちらを通ったかは ACL 経由では区別できない。**外部から観察可能な保証** (prior content
  生存) だけを assert する形にすることで、内部実装変更に強いテストになる
- `Set-Acl` は現在ユーザー SID に対して行う。プロセス token が SID を持つ全てのグループを
  Deny 対象に含めれば良い理論があるが、実装複雑度と発現ケースの狭さから見送り

**Result**: PR #41 マージ、#30 Part 1 完了。

### issue #30 Part 2 → 対応なし close

#### 問題
`codex-wrapper.ps1` の Fix C (`try { ... } finally { Cleanup }`) は通常の `Ctrl-C (SIGINT)`
では動作するが、親プロセスが `WM_CLOSE` や `taskkill /F` で PS を殺した場合は `finally` が
skip され、staging directory (`$env:TEMP\codex-media-<GUID>`) が残留する。

これは PS 5.1 の言語仕様上の限界で、完全解決は PowerShell 7+ 移行または外部プロセス監視でしか
達成できない。

#### 判断過程
当初は「起動時に 24h+ の `codex-media-*` を sweep する軽量 secondary defense (10 行の
実装) を追加」の案を検討していたが、Yumeno さんから「%TEMP% に残置されるとなにが問題に
なりますか」の問いを受けて実害を洗い直した:

| 観点 | 影響 |
|---|---|
| ディスク容量 | 1 回数 MB〜数十 MB、累積しても現代のディスク容量では問題にならない |
| セキュリティ・プライバシー | 中身は元ファイルの複製 (ユーザー自身が Codex に送るために選んだ画像)。元ファイルより秘匿性が上がるわけではない。%TEMP% の権限は user profile と同等 |
| パフォーマンス | 通常アプリの動作に影響しない |
| 見た目 | Explorer で %TEMP% を開くと `codex-media-*` が並んで見えるだけ |

つまり実質的には **%TEMP% の視覚的汚染のみ**。

追加で調査したこと:
- Yumeno さんの端末では Storage Sense 有効 (128 = 30 日で %TEMP% 自動削除)、
  ただし **配布先ユーザーの環境で有効とは保証できない** (Storage Sense はデフォルト無効、
  ユーザーが有効化する必要がある)
- 発現条件が狭い: attachment 付き実行 + WM_CLOSE/taskkill 系強制終了 の複合

#### 結論
Yumeno さんの一言「そこまでケアできてるソフトウェアってあんまりないと思いますよ」で
判断が固まった。**対応なしで close**。

- コード追加のバグリスクと防いでいる問題の実害を比較して over-engineering
- 判断過程を close コメントに明記して close (将来同じ論点が来たときに参照可能)

**Result**: 対応なし、issue #30 close。

### issue #40 → 新規起票

セッション中に判明した課題を新 issue として立てた:

- 背景: `test-install-*.sh` の rollback path が Windows で SKIP されるため、bash 側の
  rollback 診断 assertion (#29 の PR #39 で追加) と PS 側の rollback fixture (#30 Part 1
  の PR #41 で追加) はどちらも Windows の開発機では確実には走らない
- 目的: GitHub Actions で ubuntu-latest 系のワークフローを組み、Linux 環境で bash テスト
  群を自動実行する
- 論点: real codex 依存テストの扱い (推奨: 案 Y = shim のみ)、Windows runner の要否
  (この issue のスコープは Linux runner のみ、Windows runner は将来別 issue)
- 実装方針: `/codex-implement` に委任想定、workflow yaml draft を issue に添付

本セッションでは着手せず、Yumeno さんが優先度を決めた上で後日対応する扱いにした。

## 判断の記録 (方法論)

### 「そこまでケアできてるソフトウェアはあまりない」

#30 Part 2 の判断過程が重要な学び。以下の段階を辿った:

1. 私は当初 case A (起動時 sweep) を推奨、10 行の追加コードで「気持ち悪さを消せる」
2. Yumeno さんが「%TEMP% に残置されるとなにが問題ですか」と実害を尋ねる
3. 洗い出した結果、実害はほぼ視覚的汚染のみと判明
4. Yumeno さんが「Storage Sense は確実に走るのか?」で私の断定を検証させる
5. 私が「配布先環境では保証できない」と訂正し案 A を再推奨
6. Yumeno さんが「%TEMP% に残置されるとなにが問題ですか」を再度問い、私は改めて
   問題の深刻度が視覚的汚染にとどまることを認めて案 B に戻した
7. Yumeno さんの一言「そこまでケアできてるソフトウェアはあまりない」で判断が固定

**方法論として残すべき点**:
- **実害の深刻度を先に決めてから対応の要否を判断する** (対応案から入らない)
- **「気持ち悪さ」は実害ではない**、区別する
- **配布先環境の前提を仮定しない** (デフォルト無効の機能を「有効」として計算に入れない)
- **既存のソフトウェアがどこまでやっているかの相場感** を判断の参考に持つ

この過程を issue #30 の close コメントに記録して、将来同じ論点が来たときに参照可能にした。

## 関連する既知の弱点

このセッション中には触らなかったが、周辺の未対応:

- **#40 (Linux CI 自動化)**: 上述、本セッションで新規起票
- **#24 (複数メディア対応拡張)**: 音声/動画/PDF 対応、Codex CLI 側の対応形式次第
- **#20 (SKILL.md 許可傘ノウハウ重複維持ルール化)**: Phase 2c の SKILL.md 分割で状況変化

## 統計

| 項目 | 数 |
|---|---|
| 処理した issue | 4 close (#25, #29, #30, #31), 1 新規 (#40) |
| PR 数 | 2 (#39, #41) |
| 変更ファイル (合計) | 7 (installer sh × 2 + test sh × 2 + test ps1 × 2 + test-wrapper.ps1 × 1) |
| Codex 委任回数 | 0 (すべて私が直接編集、変更が小さいため) |
| 対応なしで close した P3 | 1 (#30 Part 2) |

## 参照

- 元指摘: PR #26 の Opus post-fix independent review
- 先行 refactor: issue #32 (Phase 1-4、`2026-07-08-issue-32-skill-bundled-helpers.md`)
- 続き候補: #40 (Linux CI)、#24 (メディア拡張)、#20 (docs 運用ルール)
