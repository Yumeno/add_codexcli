# Issue #24 Antigravity CLI引き継ぎ

- 作成日: 2026-07-06
- リポジトリ: `C:\Users\vz7a-\Desktop\add_codexcli`
- branch: `main`
- 対象Issue: [#24 複数メディアをCodex CLIのVLMコンテキストとして参照できるようにする](https://github.com/Yumeno/add_codexcli/issues/24)
- 引き継ぎ理由: Codex weekly limitが残り1%のため
- 重要: 追加のCodex実通信は行わず、残作業はAntigravity CLI側で継続する

## 目的

`ask-codex-with-context`から、質問・テキストcontextと単一または複数画像をCodex CLIへ渡せるようにする。
画像は順序を保持し、安全な一時領域へstagingしてから`codex exec -i`へ渡す。

## 確定した入力契約

- 公式Codexマニュアル: `--image` / `-i`は複数画像を受け付ける。
- ローカル確認: Codex CLI `0.142.5`
- `codex exec --help`: `-i, --image <FILE>...`
- カンマ結合はpath中のカンマと衝突するため不採用。
- staging後の各画像について`-i <path>`を反復する。
- 現在の対応形式はPNG/JPEGのみ。
- PDF、音声、動画、その他は`unsupported`。

## 現在の変更

未コミットの変更が存在する。既存変更を破棄、reset、checkoutしないこと。

### wrapper

- `scripts/codex-wrapper.ps1`
  - `-Attachment`: 単一画像
  - `-AttachmentList`: UTF-8、1行1pathの複数画像
  - PNG/JPEG magic bytes判定
  - directory、reparse point、空ファイル、未知形式を拒否
  - ASCII一時領域へ`image-001.png`形式でcopy
  - `manifest.json`作成
  - `MEDIA` / `MEDIA_ITEM`診断
  - `-i`反復
  - 成功、失敗、timeout時cleanup
- `scripts/codex-wrapper.sh`
  - `--attachment`反復
  - `--attachment-list`
  - PowerShell版と同じPNG/JPEG判定、staging、診断、`-i`反復、cleanup

### tests

- `scripts/tests/test-media-wrapper.ps1`
  - 通信なしのrecording shimによる専用テスト
  - 複数画像、順序、canonical extension、context併用、cleanupを確認
- `scripts/tests/test-wrapper.ps1`
  - 複数画像と未知形式拒否のケースを追加
- `scripts/tests/test-wrapper.sh`
  - 同等ケースを追加

### skills/docs

- `.claude/skills/ask-codex-with-context/SKILL.md`
- `.agents/skills/ask-codex-with-context/SKILL.md`
- `README.md`
- `docs/worklogs/2026-07-06-issue-24-multiple-images.md`
- `docs/worklogs/README.md`

## 検証済み

### 通信なし

- `scripts/tests/test-media-wrapper.ps1`: PASS
- PowerShell parser: PASS
- 未知形式として`README.md`を渡した場合:
  - exit 1
  - `[CODEX_WRAPPER_ERROR]`
  - `Unsupported or unrecognized attachment format`
- `git diff --check`: PASS

### Codex E2E

段階投入済み。これ以上のCodex通信は不要。

1. PNG 1件
   - 白地に赤い円、643 bytes
   - 8.5秒、exit 0
   - 応答: `中央に赤い円があります。`
2. JPEG 1件
   - 白地に青い正方形、1669 bytes
   - 7秒、exit 0
   - 応答: `中央に青い正方形があります。`
3. PNG/JPEG 2件
   - 7秒、exit 0
   - 応答:
     - `1枚目：円、赤`
     - `2枚目：正方形、青`

PNG/JPEGは`probe-verified`へ更新済み。

## 既知の制約・注意点

1. PowerShell外部プロセス境界では`-Attachment path1,path2`が単一文字列になる。
   - `-Attachment`は単一画像専用。
   - 複数は必ず`-AttachmentList`を使う。
   - path中のカンマを許可するため、カンマ分割を追加しない。
2. 既存`test-wrapper.ps1`全体は実Codex通信ケースを含み、120秒でtimeoutした。
   - attachment専用テストの失敗ではない。
   - 残存した子プロセスは自然終了済み。
3. bashを実行できるGit Bash/WSLがこの環境にないため、bash版は未実行。
4. `test-wrapper.sh`で追加した`mapfile`はmacOS標準Bash 3では使えない。
   - portableな`while read`等へ修正すること。
5. bash版はPowerShell版のようなJSON manifestをまだ作っていない。
   - 現状は`MEDIA` / `MEDIA_ITEM`がmanifest相当。
   - Issue要件を厳密に満たすならmanifestファイルを追加すること。
6. `scripts/tests/test-media-wrapper.ps1`がREADMEのファイル構成一覧へ未追記か確認すること。
7. PowerShell sourceはUTF-8 BOM、bash sourceはLFを維持すること。

## 残作業

1. bash実装を静的レビューする。
2. `test-wrapper.sh`の`mapfile`をBash 3互換へ修正する。
3. bash版manifestの要否を判断し、必要なら実装する。
4. PowerShellテスト追加箇所を専用テストと重複しすぎていないか整理する。
5. README、両Skill、worklogを現実装へ同期する。
6. PowerShell parser、専用テスト、`git diff --check`を再実行する。
7. bash環境が利用可能ならbashテストを実行する。
8. diffレビュー後に日本語commit、pushする。
9. Issue #24の受け入れ条件を照合し、必要ならIssueへ結果を記録する。

## 推奨開始コマンド

```powershell
git status --short
git diff --check
powershell -ExecutionPolicy Bypass -NoProfile -File scripts\tests\test-media-wrapper.ps1
```

Codex E2Eはすでに十分な結果があるため再実行しない。

一時E2Eディレクトリ`C:\tmp\codex-media-e2e`は引き継ぎ文書作成後に削除済み。
