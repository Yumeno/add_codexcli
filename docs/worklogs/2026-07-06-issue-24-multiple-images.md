# Issue #24: 複数画像attachment対応

- 作業日: 2026-07-06
- 対象Issue: [#24 複数メディアをCodex CLIのVLMコンテキストとして参照できるようにする](https://github.com/Yumeno/add_codexcli/issues/24)
- 状態: PowerShellおよびBashでの画像・manifest.jsonステージング実装完了、全テストPASS確認済み

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
- PowerShell suite (`test-wrapper.ps1`): **45件中45件PASS**。fake Codexによるtimeout、exit 2、error sentinel、attachment staging cleanupを含む。
- bash suite (`test-wrapper.sh`): Git for Windowsの`bash.exe`を明示指定し、**50件中50件PASS**。manifest検証、制御文字を含むファイル名の拒否を含む。
- manifest診断: 送信前にmanifest path、元ファイル名、staged path、MIME、byte数、support状態をstderrへ表示する。

- PowerShell timeout: fake Codexでexit 2、error sentinel、attachment staging cleanupを確認。
