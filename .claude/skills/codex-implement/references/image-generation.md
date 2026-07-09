# GPT-Image-2 画像生成・編集の技法 (codex-implement 参考文書)

`/codex-implement` で Codex CLI に画像アセットの生成・編集を委任する際に読む参考文書。
仕様書 (タスク指示) を書く前にこの文書を一読し、該当する節の技法を反映すること。

- **正本 (SSoT)**: `docs/references/image-generation.md`。skill 同梱コピー
  (`.claude/skills/codex-implement/references/`、`.agents/skills/codex-implement/references/`)
  は `tools/sync-skill-scripts` が配布する複製であり、直接編集しない
- **調査日**: 2026-07-10 (Web 調査 + 本リポジトリでの実測)
- **実測環境**: codex-cli 0.144.0、Windows 11 ネイティブ、ChatGPT アカウント認証
- **信頼度表記**: [公式] = OpenAI 公式ドキュメント/API リファレンスで確認、
  [実測] = 本リポジトリの実テストで確認、[二次] = サードパーティ情報 (裏付けの程度を併記)

## 1. Codex CLI での画像生成の仕組み [実測]

- Codex CLI は画像生成を feature flag `image_generation` (stable / 有効) として内包する。
  確認コマンド: `codex features list`
- 生成・編集とも、内部 tool `image_gen` が発動する。編集時は引数
  `referenced_image_paths` に **ローカル絶対パスの配列** で入力画像を渡す形が実測で確認された。
  wrapper の `-Attachment` は不要 — 仕様書にリポジトリ内のファイルパスを書くだけで、
  Codex が自分で画像を読み、編集入力として参照する
- **モデル名は可視化されない**。応答にもログにも生成モデル名は出ない仕様
  (公知情報として GPT-Image-2 系だが、Codex に自己申告させると推測になる)。
  仕様書でモデル名の報告を要求しない。skill のモデル名フッター規則と同じ原則で、
  **推測のモデル名を成果物や記録に書かない**
- 出力は PNG バイナリの直接ファイル書き出し (`-SandboxMode workspace-write` が必須)
- プロンプトエンジニアリングは Codex 自身が行う。仕様書に長い画像生成プロンプトを
  書く必要はなく、**要件 (何が欲しいか) を書けば Codex が構造化プロンプトに展開する**
  (実測では、仕様書の 5 行の要件から Codex が constraints / avoid 込みの詳細プロンプトを
  自動構築した)

## 2. 仕様書 (タスク指示) の書き方

### 2.1 生成タスクの必須項目 [実測]

仕様書には次を明示する。これで十分であり、細かい構図・照明指定は Codex に任せてよい:

- **ファイル名と保存先** (例: `assets/hero.png`。リポジトリ内のパスにする — 検収の前提)
- **形式** (PNG / JPEG / WEBP [公式])
- **被写体・内容** (何が写っているべきか)
- **スタイル** (アニメ調、フォトリアル、フラットイラスト等)
- **避けたい要素** (人数の制限、テキスト・ロゴ・透かしの禁止等)
- サイズの希望があれば (「1024×1024 前後」程度の緩い指定でよい)

### 2.2 こだわる場合のプロンプト構造 [公式]

Codex 任せで足りない場合、公式推奨の順序で要件を書くと安定する:
**背景/シーン → 被写体 → 重要な詳細 (素材・照明・カメラ・構図) → 制約**。
用途 (広告、UI モック、ドキュメント挿絵等) を書くと仕上げの方向が定まる。

- 二次情報 (多数のガイドが一致) では「Scene / Subject / Details / Use case / Constraints」
  の 5 スロット構成として流通している [二次・多重裏付け]

### 2.3 テキスト描画 (画像内文字) [公式]

- 描画したい文字列は **ダブルクォートで囲んで逐語指定** し、配置・役割 (見出し/ラベル等) を添える
- 公式の検証済み定型句: `Render this text verbatim. No extra characters. No duplicate text.`
- 難しい単語・ブランド名は 1 文字ずつスペルアウトすると精度が上がる
- 公式も「正確なテキスト配置と明瞭さにはまだ苦戦することがある」と留保しており [公式]、
  文字化けしたら「文字数を減らす / 文字を大きくする」方向で再試行する

### 2.4 アンチパターン

- **旧世代のキーワードスパムは効かない** (`8k, masterpiece, trending on artstation` 等)。
  自然言語の記述で書く [二次・多重裏付け。公式も構造化自然言語を推奨]
- **曖昧な品質形容詞** (`stunning`, `cinematic`) より **具体的な視覚的事実**
  (光源の向き・レンズ・質感) を書く [公式 (概念) + 二次]
- **1 プロンプトへの詰め込みすぎ** を避け、ベースを作ってから小さな変更で反復する [公式]
- **透明背景は非対応** (gpt-image-2 世代のリグレッション) [公式]。透明 PNG が必要なら
  「クロマキー色 (#00ff00 等) 背景で生成 → ローカルで色抜き」の回避策
  (openai/codex リポジトリの公式 imagegen スキルが実装している手法) [準公式]

## 3. 画像編集の技法

### 3.1 基本 [実測 + 公式]

- 編集は **自然文の変更指示で成立する**。実測では「時間帯を早朝に・髪型をポニーテールに・
  服装をセーラー服に」という 3 点指示で、キャラクターの同一性・構図・ポーズを維持した
  編集が一発で成功した
- 仕様書には **入力画像のリポジトリ内パス** と **出力ファイル名** を明示し、
  **元画像を上書きしない** (別名で保存する) 制約を入れると検収が楽になる

### 3.2 Change + Preserve の定式 [公式 (概念) + 二次 (命名)]

編集指示は「何を変えるか」だけでなく **「何を維持するか」を明示的に列挙** する:

- **Change**: 変更点を限定列挙する (「この 3 点だけ変更」)
- **Preserve**: 維持項目を具体的に列挙する。公式 Cookbook の実例:
  `Do not change her face, facial features, skin tone, body shape, pose, or identity in any way.`
- 二次情報ではこれに **Physical Realism** (接地影・質感の整合等) を加えた 3 部構成として
  流通している [二次・2 ソース一致]

**重要**: Preserve リストは **反復編集のたびに毎回再掲する** [公式]。モデルは前のターンの
制約を自動的には引き継がない。再掲を怠ると意図しない箇所まで編集が波及する (ドリフト)。

### 3.3 人物の同一性維持 (identity preservation) [公式]

「顔を変えないで」のような曖昧な指示ではなく、**属性を網羅的に列挙** する:
顔立ち・表情・肌の色・体型・髪 (色/質感)・ポーズ・服 (維持する場合)・背景・カメラアングル。
維持したい属性が多いほど列挙を省かないこと。

### 3.4 複数参照画像 [公式]

- 各入力に **インデックスと役割** を付けて参照する:
  `Image 1: 編集対象。Image 2: スタイル参照。Image 2 のスタイルを Image 1 に適用する`
- 上限: **16 枚 / 各 50MB / PNG・WEBP・JPG** [公式 API リファレンスで確認済み]
- プロンプト最大長は 32,000 文字 [公式] — 通常の仕様書で意識する必要はない

## 4. 検収 (codex-verify との関係) [実測]

- 生成物は `codex-verify check` に **untracked binary** (`?? path/to/image.png`) として出る
- 実体確認は **magic bytes** で行う: PNG は先頭 8 バイトが `89 50 4E 47 0D 0A 1A 0A`
  (`head -c 8 file.png | od -An -tx1`)。`file` コマンドでも可
- **枚数・ファイル名が事前に不明でも検収は機能する**。検収は期待値照合型ではなく
  差分検出型 (snapshot との比較) なので、clean tree ガードが効いていれば
  「実行後に存在する新規ファイル = すべて Codex の成果物」と帰属できる。
  ストーリーボードから自由に複数枚生成させる場合も、Codex の自己申告リストと
  git 実態の照合はそのまま機能する
- ただし **出力先はリポジトリ内の 1 ディレクトリに縛る** こと (名前・枚数は自由でよい)。
  リポジトリ外 (%TEMP% 等) への書き出しは git ベースの検収に映らない盲点になる
- 多枚数の場合の中身確認は、全数 magic bytes + サンプリング目視が現実的

## 5. 既知の注意点

- **Windows の旧版不具合**: codex 0.120〜0.123 で Windows/WSL の image_gen tool が
  利用不可になる不具合が報告されていた (openai/codex issues #19133, #21640)。
  さらにネイティブ Windows で **エラーを出さずプレースホルダー PNG を黙って生成する**
  ケースの報告もある。**0.144.0 での実測 (2026-07-10) では生成・編集とも正常動作**。
  古い codex で失敗する場合や、生成物が不自然に小さい/単色の場合は、まず
  `codex --version` とプレースホルダー疑いを確認する
- 生成物のバイト数が数十 KB 未満なら placeholder の疑いあり (実測の正常生成は
  1024px 級で 1.8〜1.9MB)。検収で目視を省略しない
- 日本語パス問題は wrapper (`-Cd` 指定 + ASCII パス前提) の既存ガードがそのまま適用される

## 6. 主要出典

**公式** (developers.openai.com):
- [Image generation guide](https://developers.openai.com/api/docs/guides/image-generation) — quality/サイズ/フォーマット/透明背景非対応
- [GPT Image prompting guide (cookbook)](https://developers.openai.com/cookbook/examples/multimodal/image-gen-models-prompting-guide) — プロンプト構造・編集実例・Preserve 再掲則
- [images/edit API reference](https://developers.openai.com/api/reference/resources/images/methods/edit) — 参照画像 16 枚/50MB 上限
- [gpt-image-2 model card](https://developers.openai.com/api/docs/models/gpt-image-2)

**準公式**:
- [openai/codex 組込み imagegen スキル](https://github.com/openai/codex/blob/main/codex-rs/skills/src/assets/samples/imagegen/SKILL.md) — 透明背景のクロマキー回避策
- openai/codex issues [#19133](https://github.com/openai/codex/issues/19133), [#21640](https://github.com/openai/codex/issues/21640) — Windows 旧版不具合

**二次情報** (技法の多重裏付けに使用): fal.ai / framia.converge.ai / i-scoop.eu /
pixverse.ai / atlabs.ai / upuply.com の各 GPT-Image-2 プロンプトガイド (2026)

**実測**: 本リポジトリ `docs/worklogs/` の該当 worklog (2026-07-10 画像生成・編集テスト) を参照
