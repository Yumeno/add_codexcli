# Codex CLI 画像生成・編集の応用テストと reference 文書の整備

## 背景

`/codex-implement` の応用利用テストとして「Codex に画像を生成させる」を試したところ、
当初は私 (Claude) も Codex 自身の一般知識でも「Codex CLI が画像生成能力を内包しているか」
がすぐに断定できない状態だった。ユーザーから GPT-Image-2 内包の公知情報の指摘を受けて
実機確認・実テストを行い、確認された挙動と技法を skill の参考文書として恒久化した。

体制: Fable 5 (メインループ) が指揮・統合、Web 調査は Sonnet サブエージェント 1 体に委任、
コード実装は `/codex-implement` で Codex に委任。

## 実機確認 (2026-07-10、codex-cli 0.144.0、Windows 11 ネイティブ)

- `codex features list` で `image_generation stable true` を確認
- モデルカタログ (`codex debug models`) には gpt-5.5 / gpt-5.4 / codex-auto-review のみ。
  画像生成は独立モデルではなく **内部 tool** として組み込まれている

## 応用テスト 1: 画像生成

- 仕様書: 「アニメ調女子高校生 1 名、シチュエーション任意、PNG、`test_output.png`」の
  要件 5 行程度。細かい構図・照明は指定しない
- 結果: **成功**。1254×1254 PNG (1.85MB)、magic bytes 正常、仕様どおりの画
  (放課後の教室、夕焼け、ブレザー制服、ノートを抱えた立ち姿)
- Codex は tool 呼び出しの生の記述として `image_gen.imagegen({...})` を返した。
  prompt は Codex が自動構築しており、仕様書に無い constraints
  (人数制限・年齢適正・no text/watermark・avoid photorealism 等) を自発的に補っていた
- `codex-verify check`: VIOLATION なし、untracked binary 1 件のみ

## 応用テスト 2: 画像編集 (identity preserve)

- 入力: テスト 1 の生成画像 (実験ブランチにコミットして clean tree を確保)
- 仕様書: 自然文の 3 点変更 (夕焼け→早朝、ストレートロング→ポニーテール、
  ブレザー→セーラー服) + 「それ以外は維持」+ 元画像の上書き禁止
- wrapper の `-Attachment` は使わず、**仕様書にリポジトリ内パスを書くだけ** で実行
- 結果: **一発成功**。3 点とも反映され、顔立ち・構図・ポーズ・教室はほぼ完全に維持
- tool 呼び出しの生の記述から、編集は `referenced_image_paths` (ローカル絶対パスの配列)
  + prompt (`Use case: identity-preserve`、維持項目の網羅列挙) で発動されると判明
- モデル名は応答にもログにも出ない (ユーザー指摘どおりの仕様)。仕様書で
  「モデル名の自己申告不要」と明記したのは正解だった

## 設計判断

### 専用スキル化せず codex-implement への補足とした理由

- テストで既存フロー (仕様書 → wrapper → codex-verify) が**無変更で**画像タスクに対応
  できると確認された。ガード類はタスク種別に依存しない
- 実利用は「実装指示に画像アセット生成が内包される」形が自然で、スキルを分けると
  1 タスクが 2 スキルに割れる
- スキル追加は 2 系統維持・installer・bundle 対応表の保守コストが乗る
- 「リポジトリと無関係に画像だけ欲しい」用途が頻発したら、その時に軽量専用スキルを
  検討する (YAGNI)

### reference 文書は「必要に応じて読むもの」として同梱 (progressive disclosure)

- SKILL.md は毎回コンテキストに載るため薄く保ち、画像タスクの時だけ読む詳細を
  `references/image-generation.md` に分離
- 正本は `docs/references/` (SSoT)、`tools/sync-skill-scripts` が
  `.claude/skills/codex-implement/references/` と `.agents/.../references/` へ配布
  (helper scripts と同じ SSoT → 配布の構図)。手動複製による drift (issue #20 と同型) を回避
- installer は skill ディレクトリを丸ごとコピーするため、references/ は自動的に配布に乗る

## Web 調査 (Sonnet サブエージェント委任)

OpenAI 公式ドキュメント最優先で調査し、公式 / 準公式 / 二次情報の信頼度区分と
出典 URL 付きのレポートを得た。要点:

- 公式確定値: 参照画像 **16 枚 / 各 50MB / PNG・WEBP・JPG**、プロンプト 32,000 文字、
  **透明背景は gpt-image-2 非対応** (公式リポジトリの imagegen スキルはクロマキー回避策を実装)
- 編集の核: **Change + Preserve** (公式 cookbook 実例あり)、Preserve リストは
  **反復のたびに再掲** (モデルは前ターンの制約を引き継がない)
- 複数参照は `Image 1 / Image 2` のインデックス + 役割ラベルで指示 (公式)
- 「Thinking Mode」は公式に存在しない二次情報の用語 (レポートが事実確認で棄却)、
  テキスト精度のパーセンテージ類も出典不明の数値として不採用
- Windows 旧版 (0.120〜0.123) の image_gen 不具合報告 (openai/codex #19133, #21640)。
  「エラーを出さずプレースホルダー PNG を黙って生成する」報告もあり、
  **生成物のバイト数確認と目視を検収から省かない** 根拠として文書に反映
  (0.144.0 実測では正常動作)

調査エージェントは 1 体のみ (レートリミット配慮、一斉 fan-out を避ける方針)。

## 実装 (Codex 委任 + host 側補完)

- `tools/sync-skill-scripts.{sh,ps1}`: skill → reference files の対応表を追加。
  配布 (delete-then-copy、未対応 skill の references/ は削除)、検証 (byte 一致 +
  期待外検出 + 未対応 skill にディレクトリがあれば mismatch) の両モード対応
- bash 版のディレクトリ作成が `make_dir()` (subshell cd + 相対 mkdir) に変わった。
  Codex sandbox で絶対 `/c/...` の `mkdir -p` が失敗するための回避だが、host では
  等価動作で、以後の Codex 委任にも耐性がつくためそのまま採用
- `codex-implement/SKILL.md` (両系統) に画像アセット節 + references への差し先を追加
- **Codex sandbox の `.agents/` ACL 拒否が 3 回目の再発**。今回は仕様書に
  「失敗したらリトライせず未完了報告」を事前明記していたため、Codex は正直に
  未完了 3 項目を報告して終了。host 側で sync 再実行 + `.agents` の SKILL.md 追記で補完。
  この「事前に fallback を宣言して分担する」形は今後の `.agents/` 絡み委任の定型にできる

## テスト結果 (host 側)

- `sync-skill-scripts --check` / `-Check`: PASS
- `test-skill-bundles.{sh,ps1}`: PASS
- `test-install-{antigravity,claude-code}.{sh,ps1}`: PASS (read-only は Windows で SKIP、既存どおり)
- `codex-verify check`: VIOLATION なし (テスト 1・2・実装委任の全 3 回とも)

## 残課題・メモ

- ストーリーボード等からの複数枚自由生成は未実測 (検収は差分検出型なので枚数・名前
  不明でも機能する設計であることは文書化済み。出力先ディレクトリだけ縛る運用)
- 透明背景が必要な用途が出たら、公式 imagegen スキルのクロマキー手法の移植を検討
- 実験ブランチ `experiment/codex-image-gen-test` (テスト画像コミット入り) は本 PR
  マージ後に削除する
