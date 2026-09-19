# Issue #44: 画像生成・編集ガイドの GPT Image 2.5 対応と E2E 実測

## 背景

`docs/references/image-generation.md` は 2026-07-10 の GPT-Image-2 調査と codex-cli 0.144.0 の
実測を基準にしていた。OpenAI 公式資料が GPT Image 2.5 (Sunburst / Flare) に更新されたため、
Issue #44 の文案に沿って参考文書を改訂し、代表 5 ケースを Codex CLI で実測した。

体制: Fable 5.1 (メインループ) が調査・E2E 指揮・検収、参考文書の改訂は Sonnet サブエージェント
1 体に委任、画像生成・編集は `/codex-implement` で Codex に委任。

## 環境

- codex-cli 0.154.0、Windows 11 ネイティブ、ChatGPT アカウント認証
- 実行場所: git worktree `C:/Users/vz7a-/Desktop/add_codexcli-e2e` (ASCII パス)、
  ブランチ `exp/issue-44-image-e2e` (main へはマージしない。生成画像は同ブランチの
  `e2e/issue-44/` にコミット済み)
- wrapper: `.claude/skills/codex-implement/scripts/codex-wrapper.ps1`、
  `-SandboxMode workspace-write`、`-Model` 未指定
- 検収: `codex-verify.ps1` の snapshot / check (全ケース VIOLATION なし、untracked binary のみ) に
  加え、Python 標準ライブラリ (struct / zlib) で PNG をデコードして alpha を独立計測、
  Read tool で目視

## 事前確認 (画像を生成しない probe)

- `codex features list`: `image_generation stable true`、`view_image stable true`
- Codex に read-only で内部画像ツールの定義を列挙させた結果、ツール名 `image_gen.imagegen`、
  引数は `prompt` (string、必須) / `referenced_image_paths` (Array<string> | null、絶対パス) /
  `num_last_images_to_include` (integer | null) の 3 つのみ。`model` / `quality` / `size` /
  `background` / `output_format` / `mask` は定義なし
- 画像モデル名はツール定義・応答・ログのいずれからも取得不可
- openai/codex 組込み imagegen skill (2026-09-19 確認) は built-in `image_gen` に
  「本物の透明背景を依頼しアルファを保持する」方針に変わっており、7 月時点で参照した
  クロマキー回避策の記載はない

## E2E 結果

全ケースとも Codex は仕様書の要件から構造化プロンプト (Use case / Asset type / Constraints /
Avoid 等) を自動構築した。出力先パス・形式・サイズ・品質・透過はツール引数に無いため
prompt 内の自然文で伝え、生成後に指定パスへ配置していた。

| ケース | 出力 | 結果 | 実測値 |
|---|---|---|---|
| 1. 透明背景の 2D 素材 (生成) | `case1_mechanic.png` | 合格 (2 回目で透過取得) | 1024×1536 RGBA。alpha=0 が 70.7%、被写体は alpha 253〜254 (255 は 0 画素)、alpha 1〜63 の薄い暈しが 1.8%。四隅 alpha=0。余白 (alpha>63): 上 8 / 下 15 / 左 270 / 右 212 px |
| 2. 日本語文字入り (生成) | `case2_sign.png` | 合格 (1 回) | 1536×1024。「整備中」「午後3時まで」各 1 回、誤字・余計な文字なし、可読 |
| 3. 上着の色変更 (編集) | `case3_mechanic_navy.png` | 合格 (1 回) | 1024×1536 RGBA。つなぎのみ紺色化、顔・工具・ブーツ・線画維持。alpha=0 70.62% (元 70.70%) |
| 4. 複数参照による衣装変更 (生成 + 編集) | `case4_ref_outfit.png`、`case4_mechanic_chef.png` | 合格 (各 1 回) | 参照は RGB (color type 2)。出力は RGBA、alpha=0 70.51%。Image 2 の衣装 (白コックコート + 黒エプロン) のみ反映、Image 1 の顔・ポーズ・工具・ゴーグル・ブーツ維持、Image 2 の人物は混入なし |
| 5. 連続編集 (編集 ×2) | `case5_step1_cap.png`、`case5_step2_boots.png` | 変更点は反映、保持対象にドリフトあり | 編集 1: 赤キャップ追加・ゴーグル維持。ただし **つなぎが濃紺から明るい青に変化** (指示外)。編集 2: ブーツ黒化・キャップ維持。ただし **下端余白が 0 (足元が画像端に接触)**。alpha=0 70.37% → 70.16% |

### 観察事項

- **透明背景は Codex CLI 経由で自然文リクエストのみで取得できた** (ケース 1 は 1 回目で
  失敗し 2 回目で成功。Codex の自己申告)。編集経路 (ケース 3〜5) では入力の透過が維持された
- 透過出力の被写体は alpha 253〜254 で、完全不透明 (255) の画素が存在しない。ゲーム素材として
  実用上は問題ないが、「alpha=255 の画素があること」を検収条件にすると不合格になる
- 被写体の外周に alpha 1〜63 の広い暈しがあり、黒背景上では暗いハロとして見える。
  明るい背景に置く用途では輪郭の色残りとして確認が必要
- 「四辺に余白」の指示は上下 8〜16px と極薄で満たされ、連続編集ではさらに詰まって 0 になった。
  余白が必須なら px 数や比率で指定し、出力後に計測する
- 連続編集では、変更対象外の色 (つなぎ) が変わる drift が 1 回目で発生した。保持条件を毎回
  全列挙しても防げていない。採用済み画像を入力にする運用と、出力後の保持対象の比較は必須
- 文字描画 (日本語 3 文字 + 6 文字) は 1 回で正確だった。サンプル 1 件のため一般化しない
- 全ケースで Codex は画像モデル名を「取得不可」と報告した (仕様書で推測禁止を明記)

## 参考文書の改訂

- `docs/references/image-generation.md` を Issue #44 §1〜§12 に沿って改訂 (Sonnet サブエージェント)。
  [公式/API] / [CLI実測] / [推奨] / [未検証] の区分を導入し、公式仕様の確認日 (2026-09-19) と
  CLI 実測日 (2026-09-19 と 2026-07-10) を分離。E2E 結果は「実測記録」節に追記
- 両ホストの `codex-implement/SKILL.md` の要約を Issue §12 の 8 箇条に更新
- 同梱コピーは `tools/sync-skill-scripts` で配布

## 実施していないこと

- API 直接呼び出し (quality / size / background 指定) の検証。本リポジトリの経路外
- WebP 出力、マスク編集、`num_last_images_to_include` の挙動確認
- 品質・速度の比較 (Flare / Sunburst の切替は Codex CLI 経路では不可)
