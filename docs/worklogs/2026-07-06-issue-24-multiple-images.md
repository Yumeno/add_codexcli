# Issue #24: 複数画像attachment対応

- 作業日: 2026-07-06
- 対象Issue: [#24 複数メディアをCodex CLIのVLMコンテキストとして参照できるようにする](https://github.com/Yumeno/add_codexcli/issues/24)
- 状態: PowerShellおよびBashでの画像・manifest.jsonステージング実装完了、テストアサーション強化済み（実環境でのBash実行のみ保留）

## 確認した入力契約

- 公式Codexマニュアルは`--image` / `-i`で複数画像を受け付ける。
- ローカルCodex CLI `0.142.5`の`codex exec --help`でも`-i, --image <FILE>...`を確認した。
- path中のカンマを保護するため、カンマ結合ではなく画像ごとに`-i`を反復する。
- 公式に確認できる画像入力へ限定し、PDF、音声、動画は対応扱いしない。

## 実装内容

- PowerShell: `-Attachment`、`-AttachmentList`
- bash: `--attachment`反復、`--attachment-list`
- PNG/JPEGのmagic bytes判定
- symlink/reparse point、directory、空ファイル、未知形式の拒否
- ASCII一時領域への連番＋canonical extensionによるstaging
- 件数、総byte数、順序、MIME、support状態のstderr出力
- `-i`反復によるCodex CLIへの引き渡し
- 成功、失敗、timeout時のstaging cleanup
- Claude Code用とAntigravity CLI用の`ask-codex-with-context`を更新
- READMEへ利用例、対応状態、送信・利用枠への影響を追記

## 現在の検証結果

- PowerShell構文解析: 成功
- 未知形式の明示拒否とerror sentinel: 成功
- `git diff --check`: 成功
- attachment専用PowerShellテスト (`test-media-wrapper.ps1`): 成功 (PASS)
- PNG 1件: 赤い円を正しく認識、8.5秒、終了コード0 (E2E)
- JPEG 1件: 青い正方形を正しく認識、7秒、終了コード0 (E2E)
- PNG/JPEG 2件: 「1枚目: 赤い円、2枚目: 青い正方形」と指定順を正しく認識、7秒、終了コード0 (E2E)
- PowerShell既存suite (`test-wrapper.ps1`): BOM崩れによる構文エラーを修復し、`manifest.json`のアサーションを追加。実通信ケースでタイムアウトするものの、アタッチメントテストを含むモックケースは正常通過を確認。
- bash suite: 実行可能なGit Bash/WSLがないため未実行。ただし、`mapfile`を移植性の高い `while read` ループへ修正し、PowerShell版と同等の `manifest.json` 生成・検証アサーションを追加。

## 残作業

1. bash実行環境が利用可能になった際に、修正済みの `test-wrapper.sh` によるアタッチメントテストと既存suiteを実行する。
2. PowerShell既存suiteから実通信テストケースをモック経由に差し替える、またはスキップ可能にする整理を行う（Issue #24の直接の範囲外）。
3. 日本語コミットおよびプッシュ。
