# add_codexcli

Claude Code から OpenAI Codex CLI にセカンドオピニオンを求めるためのスキル。

## 概要

Claude Code での作業中に、Codex CLI（gpt-5.5）へ質問・監査・レビューを依頼できるカスタムスキルを提供します。

- **`/ask-codex`** — 質問テキストを Codex に投げてセカンドオピニオンを得る
- **`/ask-codex-with-context`** — 現在のファイルや git diff を添えて Codex に渡す
- **`/codex-implement`** — Codex CLI をサブエージェント（実装作業者）として使い、プロジェクト内のファイルを直接編集させる
- **`/list-codex-models`** — Codex CLI が認識しているモデル名一覧を取得（`--model` に渡せる値の確認用）
- **`/set-codex-model`** — デフォルトモデルを `codex-wrapper.conf` に保存／現状確認

## 前提条件

- [Claude Code](https://claude.ai/code)（CLI / Desktop / Web いずれか）
- [Codex CLI](https://github.com/openai/codex) v0.117.0 以上
  ```bash
  npm install -g @openai/codex
  ```
- ChatGPT Plus/Pro アカウントで `codex login` 済み、または `OPENAI_API_KEY` 環境変数を設定済み

## インストール

### 対応ホスト

| ホストCLI | 正本 | Skillの配置先 (既定) | インストーラー |
|---|---|---|---|
| Claude Code | `.claude/skills/` | `~/.claude/skills/` | `scripts/install-for-claude-code.{sh,ps1}` |
| Antigravity CLI | `.agents/skills/` | `~/.gemini/antigravity-cli/skills/` | `scripts/install-for-antigravity.{sh,ps1}` |

両ホストではtool名、permission、引数の扱いが異なるため、`.claude/skills/`と`.agents/skills/`を
別正本として維持します。各Skillは自身の`scripts/`サブディレクトリにhelperを同梱しており、
インストーラーはSkillディレクトリを丸ごとホストへ配置します。共通scriptsを別ディレクトリへ
配布する運用は廃止されました。

`codex-wrapper`の設定 (`--set-model`で保存するデフォルトモデル) は、ホスト間で共有される
`$HOME/.agents/add_codexcli/codex-wrapper.conf` に格納されます (Windowsでは
`%USERPROFILE%\.agents\add_codexcli\codex-wrapper.conf`)。`CODEX_WRAPPER_CONFIG` 環境変数で
上書きできます。

### Claude Codeへインストール

**Windows PowerShell 5.1+:**

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File scripts/install-for-claude-code.ps1
```

**Linux / macOS / WSL / Git Bash:**

```bash
bash scripts/install-for-claude-code.sh
```

既定の配置先は`~/.claude/skills/`です。別の場所へインストールする場合は第1引数
(bash) / `-DestinationRoot` (PowerShell) で親ディレクトリを指定します
(その下に`skills/<name>/`が置かれます)。

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File scripts/install-for-claude-code.ps1 `
  -DestinationRoot "C:\path\to\claude-home"
```

```bash
bash scripts/install-for-claude-code.sh "/path/to/claude-home"
```

インストール後、Claude Codeを再起動すると `/ask-codex`、`/ask-codex-with-context`、
`/codex-implement`、`/list-codex-models`、`/set-codex-model` が slash command として使えます。
各SkillのSKILL.mdは自身の`scripts/`ディレクトリを絶対パスに解決してhelperを呼ぶため、
グローバル・プロジェクトローカルどちらのインストール先でも同じように動作します。

### Antigravity CLIへインストール

この対応は、Antigravity CLIから本リポジトリのSkillを使ってCodex CLIを呼び出すものです。
Antigravity CLI自体をCodexのbackendとして扱う変更ではありません。

**Windows PowerShell 5.1+:**

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File scripts/install-for-antigravity.ps1
```

**Linux / macOS / WSL:**

```bash
bash scripts/install-for-antigravity.sh
```

動作確認環境はAntigravity CLI `1.0.16`（Windows 11）です。
探索先は公式の[Plugins & skills](https://antigravity.google/docs/cli-plugins)および
[Gemini CLI migration](https://antigravity.google/docs/gcli-migration)に基づきます。

既定の配置先は`~/.gemini/antigravity-cli/skills/`です。別の場所へインストールする場合は
`install-for-claude-code`と同じ形式で親ディレクトリを指定します。

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File scripts/install-for-antigravity.ps1 `
  -DestinationRoot "C:\path\to\antigravity-cli"
```

```bash
bash scripts/install-for-antigravity.sh "/path/to/antigravity-cli"
```

インストーラーはこのリポジトリが管理する同名5 Skillだけを更新します。ほかのSkillは削除しません。
アンインストール時は、配置先から次の5ディレクトリを削除してください。

- `ask-codex`、`ask-codex-with-context`、`codex-implement`、`list-codex-models`、`set-codex-model`

インストール後にAntigravity CLIを再起動すると、5 Skillがslash commandとして自動importされます。
現行CLIにはSkill一覧専用のサブコマンドがないため、TUIで`/ask-codex`等を入力して認識を確認します。
CLIのバージョンにより探索先が異なる場合は、`DestinationRoot`を明示して再インストールしてください。

Antigravity CLIのpermission設定はClaude Codeの許可傘とは別管理です。初回のwrapper実行時に
`command(...)`の承認が求められる場合は、表示された実コマンドを確認して許可してください。
Claude Code用の許可設定をAntigravityへ自動移植したり、`--dangerously-skip-permissions`を
有効化したりはしません。

### 旧配置からの移行

Skill内`scripts/`同梱への移行前 (2026-07以前) にインストール済みの場合、旧配置に配布された
helperは新Skillからは参照されないため、放置しても害はありませんが手動で掃除できます。

**Claude Codeの旧配置** (対象環境のみ):

```bash
# bash
rm -f ~/.claude/scripts/codex-wrapper.ps1 ~/.claude/scripts/codex-wrapper.sh
rm -f ~/.claude/scripts/codex-verify.ps1 ~/.claude/scripts/codex-verify.sh
rm -f ~/.claude/scripts/list-codex-models.ps1 ~/.claude/scripts/list-codex-models.sh
rm -f ~/.claude/scripts/codex-wrapper.conf  # モデル設定は $HOME/.agents/add_codexcli/ へ移行
```

```powershell
# PowerShell
Remove-Item "$env:USERPROFILE\.claude\scripts\codex-wrapper.ps1", `
            "$env:USERPROFILE\.claude\scripts\codex-wrapper.sh", `
            "$env:USERPROFILE\.claude\scripts\codex-verify.ps1", `
            "$env:USERPROFILE\.claude\scripts\codex-verify.sh", `
            "$env:USERPROFILE\.claude\scripts\list-codex-models.ps1", `
            "$env:USERPROFILE\.claude\scripts\list-codex-models.sh", `
            "$env:USERPROFILE\.claude\scripts\codex-wrapper.conf" -ErrorAction SilentlyContinue
```

**Antigravity CLIの旧配置** (helper配布先が`~/.gemini/scripts/`だった環境のみ):

```bash
rm -f ~/.gemini/scripts/codex-wrapper.ps1 ~/.gemini/scripts/codex-wrapper.sh
rm -f ~/.gemini/scripts/codex-verify.ps1 ~/.gemini/scripts/codex-verify.sh
rm -f ~/.gemini/scripts/list-codex-models.ps1 ~/.gemini/scripts/list-codex-models.sh
rm -f ~/.gemini/scripts/codex-wrapper.conf
```

`~/.claude/scripts/` および `~/.gemini/scripts/` を他のツールと共有していない場合は、
ディレクトリごと削除しても構いません。`~/.claude/skills/<name>/` と
`~/.gemini/antigravity-cli/skills/<name>/` は新配置なので削除しないでください。

以前保存していたモデル設定 (`codex-wrapper.conf` の `model=<name>`) は、必要なら新配置に
反映してから旧ファイルを削除してください:

```bash
# bash
mkdir -p "$HOME/.agents/add_codexcli"
bash ~/.claude/skills/set-codex-model/scripts/codex-wrapper.sh --set-model "<以前のモデル名>"
```

## 使い方

### /ask-codex — シンプルな質問

Claude Code のプロンプトで：

```
/ask-codex この設計パターンはシングルトンとファクトリどちらが適切？
```

Claude が Codex CLI を呼び出し、回答を取得して表示します。

**使用例：**
```
/ask-codex Rustのライフタイムについて簡単に説明して
/ask-codex このエラーの原因は何？ "TypeError: Cannot read property 'map' of undefined"
/ask-codex React vs Vue、小規模プロジェクトにはどちらが向いている？
```

スラッシュコマンドを使わず、Claude に直接「Codex にも聞いてみて」と頼むこともできます（自動呼び出し設定が有効な場合）。

### /ask-codex-with-context — コンテキスト付き

ファイルや差分を添えて、より的確なセカンドオピニオンを得る：

```
/ask-codex-with-context レビューして
/ask-codex-with-context src/main.ts この設計で大丈夫？
/ask-codex-with-context security-check
```

**キーワードによる自動コンテキスト収集：**

| キーワード | 収集されるコンテキスト |
|---|---|
| `review`, `レビュー`, `diff` | `git diff` + `git diff --staged` |
| `security`, `セキュリティ`, `監査` | `git diff` + 変更ファイル一覧 |
| `log`, `履歴` | `git log --oneline -20` |
| ファイルパス（例: `src/main.ts`） | そのファイルの内容 |

#### 複数画像を添付

Codex CLIの`-i`入力を使い、PNG/JPEGを複数指定できます。

```powershell
Set-Content -Encoding UTF8 attachments.txt "C:\images\first.png","C:\images\second.jpg"
powershell -File scripts/codex-wrapper.ps1 -Prompt "2枚を順番に比較して" `
  -AttachmentList "attachments.txt"
```

```bash
bash scripts/codex-wrapper.sh --prompt "2枚を順番に比較して" \
  --attachment "/images/first.png" --attachment "/images/second.jpg"
```

PowerShellの`-Attachment`は単一画像用です。複数画像は`-AttachmentList`を使います。
`-AttachmentList` / `--attachment-list`では、UTF-8のpath一覧を1行1件で指定できます。
wrapperはmagic bytesを確認し、ASCII一時領域へ`image-001.png`のような安全な名前でcopyしてから
指定順に送信します。一時copyは成功・失敗・timeout時に削除され、元ファイルは変更しません。
送信前にstderrへ件数、総byte数、manifest pathと各画像の順序・元ファイル名・staged path・
MIME・サポート状態を表示します。

| 形式 | 状態 |
|---|---|
| PNG | `probe-verified`（実画像の内容認識を確認済み） |
| JPEG | `probe-verified`（実画像の内容認識を確認済み） |
| PDF、音声、動画、その他 | `unsupported` |

画像はOpenAIへ送信され、入力サイズに応じてtoken、利用枠、処理時間へ影響します。
画像内の指示はuntrusted inputとして扱い、送信範囲や権限を拡大しません。

### /codex-implement — Codex にファイル編集を任せる

`/ask-codex` 系がすべて read-only（回答を返すだけ）なのに対し、`/codex-implement` は
Codex CLI を **サブエージェント（実装作業者）** として使い、対象リポジトリ内のファイルを
Codex 自身に直接作成・編集させます。Claude 側のトークン消費を Codex にオフロードし、
レートリミット対策として実装作業を丸ごと委任したい場合に使います。

```
/codex-implement README のタイポを修正して
/codex-implement src/utils.ts に日付フォーマット関数を追加して、対応するテストも書いて
```

#### 安全設計

- **clean tree 必須**: 実行前に `git status --porcelain` が空であることを確認する。
  未コミットの変更が残っていると中断する（Codex の変更と既存の変更が混ざるのを防ぐため）。
  あわせて実行前の HEAD / branch を記録し、実行後に Codex が git 操作をしていないか照合する
- **workspace-write sandbox**: Codex には `-SandboxMode workspace-write` と `-Cd`（対象
  リポジトリ）を渡す。ただし実際の書き込み可能範囲は Codex CLI の sandbox 実装と設定に
  依存するため、リポジトリ外への書き込み不可はこのスキル単体では保証しない
- **git でレビュー・巻き戻し**: 未コミットの変更は `git diff` で確認できる。
  `git checkout -- .` && `git clean -fd` で戻せるのは **unstaged の tracked 変更 + untracked
  ファイルのみ** で、staged 変更が検出された場合は
  `git restore --source=<実行前HEAD> --staged --worktree -- .` && `git clean -fd` を使う。コミット済み・
  branch 切替が検出された場合は固定手順で戻さず、状況確認のうえ個別判断とする。
  また、git 履歴の操作、ignored ファイル（`.env` 等）、リポジトリ外への変更、外部サービスへの
  副作用は git では戻せないため、別途確認が必要（スキル側では Codex への仕様書で git 操作・
  保護対象ファイルへの接触を禁止し、実行後に HEAD 比較で逸脱を検出する）
- **検収フロー**: スナップショットと検査は専用スクリプト `scripts/codex-verify.sh` / `.ps1` で
  スクリプト化されている（実行前に `snapshot` で HEAD / branch / status / 保護対象ファイルの
  ハッシュを記録し、実行後に `check` で HEAD・branch の一致、保護対象のハッシュ比較、
  `git status --porcelain=v1 --untracked-files=all` / `git diff HEAD --stat` のサマリを機械的に
  検査。違反は行頭 `[CODEX_VERIFY_VIOLATION]` で報告される）。手作業の git コマンド列を
  LLM が誤読・省略するリスクを減らしている。その上で Codex 自身が報告した変更ファイル一覧と
  突き合わせ、不一致があれば警告する

#### 制約

- 対象リポジトリの絶対パスは **ASCII のみ** 対応（Codex CLI の WebSocket 層の制約）。
  日本語などの非 ASCII パスの場合は、`git worktree add -b codex-work-<name> C:/tmp/work-<name>` のように
  ASCII パスの worktree を切って、そちらで実行する
- このスキルは Codex に **ファイル編集権限を与える** 点が他の Codex スキルと異なる。
  `disable-model-invocation: true`（手動起動のみ）を維持し、自然言語での自動呼び出しは
  有効にしないこと

#### 責任分界

このスキルの守備範囲は **変更の検出・可視化・記録** まで（「変更の記録係」であって
「金庫の見張り番」ではない）。対象リポジトリに漏れて・壊れて困るもの（秘密情報等）が
あるかどうかの判断、そのリポジトリでこのスキルを使うかどうかの判断、検収報告を見た上での
最終的な採否は **ユーザーの責任範囲** であり、スキル側では肩代わりしない。

### /set-codex-model — デフォルトモデルの保存・確認

毎回 `--model` を打ちたくない場合、デフォルトを設定ファイルに保存できます。

```
/set-codex-model                       # 現状を表示
/set-codex-model gpt-5.5         # 既定モデルを保存
```

設定ファイルはホスト間で共有される単一の場所に置かれます:

| 環境 | 設定ファイルの場所 |
|---|---|
| bash 系 (Linux / macOS / WSL / Git Bash) | `$HOME/.agents/add_codexcli/codex-wrapper.conf` |
| Windows PowerShell | `%USERPROFILE%\.agents\add_codexcli\codex-wrapper.conf` |

`CODEX_WRAPPER_CONFIG` 環境変数を設定すれば別の場所を指せます (テストや複数プロファイル運用向け)。
両ホストのSkillはこの同じファイルを読むため、`/set-codex-model`で一度保存すれば
Claude CodeでもAntigravity CLIでも同じデフォルトが使われます。

#### モデル解決の優先順位

ラッパーは次の順に解決します（上ほど優先）:

1. CLI 引数 `--model` / `-Model`
2. 環境変数 `$CODEX_WRAPPER_MODEL`
3. `codex-wrapper.conf` の `model=...` 行
4. なし → codex CLI のデフォルトに委任（SKILL のフッターはモデル名を表示しない）

#### 直接編集する場合

ファイルは `key=value` 形式（`#` 始まりはコメント）:

```ini
# codex-wrapper.conf
model=gpt-5.5
```

#### CLI から直接操作

```bash
# bash
bash scripts/codex-wrapper.sh --set-model gpt-5.5
bash scripts/codex-wrapper.sh --show-model

# PowerShell
powershell -File scripts/codex-wrapper.ps1 -SetModel gpt-5.5
powershell -File scripts/codex-wrapper.ps1 -ShowModel
```

### /list-codex-models — モデル一覧

Codex CLI が認識しているモデル名を一覧表示。`--model` に何を渡せるか確認したい時に。

```
/list-codex-models
/list-codex-models json
/list-codex-models bundled
```

| キーワード | 動作 |
|---|---|
| なし | モデル名の plain list |
| `json`, `生` | `codex debug models` の raw JSON |
| `bundled`, `オフライン` | バイナリ同梱カタログのみ（ネットワーク非接続） |

### 自動呼び出しの設定

デフォルトでは両スキルとも `disable-model-invocation: true`（手動起動のみ）です。「Codex にも聞いて」のような自然言語で Claude に自動呼び出しさせたい場合は、SKILL.md のフロントマターを変更してください。

```yaml
# .claude/skills/ask-codex/SKILL.md
disable-model-invocation: false   # 自然言語で自動呼び出し可能にする
```

| 設定 | 動作 |
|---|---|
| `true`（デフォルト） | `/ask-codex` スラッシュコマンドでのみ起動。安全・コスト管理向き |
| `false` | Claude が文脈から判断して自動的に Codex を呼べる。利便性重視 |

> **注意:** `ask-codex-with-context` を `false` にすると、ファイル内容や差分が自動的に OpenAI に送信される場合があります。秘匿情報を含むプロジェクトでは `true` のまま使うことを推奨します。

## ファイル構成

正本 (Single Source of Truth):

```
scripts/                               # helper 正本 (SSoT)
├── codex-wrapper.{ps1,sh}             # メイン wrapper (PowerShell / bash)
├── codex-verify.{ps1,sh}              # /codex-implement 用 検収ヘルパー
├── list-codex-models.{ps1,sh}         # 利用可能モデル一覧ヘルパー
├── install-for-claude-code.{ps1,sh}   # Claude Code 用インストーラー
├── install-for-antigravity.{ps1,sh}   # Antigravity CLI 用インストーラー
└── tests/
    ├── test-wrapper.{ps1,sh}          # wrapper ユニットテスト
    ├── test-verify.{ps1,sh}           # codex-verify テスト
    ├── test-list-models.{ps1,sh}      # list-codex-models テスト
    ├── test-install-claude-code.{ps1,sh}   # Claude Code インストーラーのテスト
    ├── test-install-antigravity.{ps1,sh}   # Antigravity インストーラーのテスト
    ├── test-skill-bundles.{ps1,sh}    # 各Skill同梱helperと正本の同期検証
    ├── test-media-wrapper.ps1         # 画像attachment関連の追加テスト
    └── test-e2e.sh                    # E2E テスト

tools/
└── sync-skill-scripts.{ps1,sh}        # 正本 scripts/ → 各Skill同梱 scripts/ の同期tool
```

Skill配置 (Claude Code / Antigravity CLI 両ホスト):

```
.claude/skills/<name>/                 # Claude Code 用 (Yumeno向けの一次正本)
├── SKILL.md                           # Skill定義 (frontmatter に disable-model-invocation)
└── scripts/                           # helper 同梱 (正本の複製)
    ├── codex-wrapper.{ps1,sh}
    ├── codex-verify.{ps1,sh}         # codex-implement のみ
    └── list-codex-models.{ps1,sh}    # list-codex-models のみ

.agents/skills/<name>/                 # Antigravity CLI 用
├── SKILL.md                           # Skill定義 (frontmatter は name+description のみ)
└── scripts/                           # helper 同梱 (同上)
    └── ...
```

`<name>` は `ask-codex` / `ask-codex-with-context` / `codex-implement` /
`list-codex-models` / `set-codex-model` の 5 種類。各Skillは自身の`scripts/`に、
そのSkillが必要とする helper だけ (許可リスト方式) を同梱します。SKILL.md はいずれも
自身のディレクトリ直下の `scripts/` を絶対パスに解決してから helper を呼びます
(`$CLAUDE_SKILL_DIR/scripts/...` あるいは実行時に LLM が解決したパス)。

`tools/sync-skill-scripts` は正本 `scripts/` からSkill同梱 `scripts/` へ複製する
配布モードと、同期の検証 (`--check`) の両方を持ちます。`test-skill-bundles` はこの
`--check` を薄くラップした CI 用ガードです。

モデル設定 `codex-wrapper.conf` は **リポジトリ内には置きません**。
既定は `$HOME/.agents/add_codexcli/codex-wrapper.conf` (Windowsでは
`%USERPROFILE%\.agents\add_codexcli\codex-wrapper.conf`) で、`CODEX_WRAPPER_CONFIG`
環境変数で上書きできます。

## 利用可能なモデル一覧の取得

`--model` に何を渡せるか確認するためのヘルパー。内部で `codex debug models` を呼びます。

```bash
# bash
bash scripts/list-codex-models.sh              # モデル名一覧（推奨）
bash scripts/list-codex-models.sh --bundled    # バイナリ同梱カタログのみ（オフライン）
bash scripts/list-codex-models.sh --json       # 生の JSON

# PowerShell
powershell -File scripts/list-codex-models.ps1
powershell -File scripts/list-codex-models.ps1 -Bundled
powershell -File scripts/list-codex-models.ps1 -Json
```

> **注意:** モデルカタログに載っていても、認証種別（ChatGPT Plus / API キー）によって実際に使えるモデルは異なります。表示されたからといって全て選べるとは限りません。実際に通るかは `--model <name>` でリクエストを投げて確認してください。

## テスト

```bash
# PowerShell 版（Windows）
powershell -ExecutionPolicy Bypass -File scripts/tests/test-wrapper.ps1
powershell -ExecutionPolicy Bypass -File scripts/tests/test-verify.ps1
powershell -ExecutionPolicy Bypass -File scripts/tests/test-list-models.ps1
powershell -ExecutionPolicy Bypass -File scripts/tests/test-install-claude-code.ps1
powershell -ExecutionPolicy Bypass -File scripts/tests/test-install-antigravity.ps1
powershell -ExecutionPolicy Bypass -File scripts/tests/test-skill-bundles.ps1
powershell -ExecutionPolicy Bypass -File scripts/tests/test-media-wrapper.ps1

# bash 版（Linux/macOS/WSL/Git Bash）
bash scripts/tests/test-wrapper.sh
bash scripts/tests/test-verify.sh
bash scripts/tests/test-list-models.sh
bash scripts/tests/test-install-claude-code.sh
bash scripts/tests/test-install-antigravity.sh
bash scripts/tests/test-skill-bundles.sh

# E2E テスト
bash scripts/tests/test-e2e.sh
```

`test-skill-bundles` は各Skillの同梱 `scripts/` が正本 `scripts/` と byte単位で一致
していることを検証します。SKILL.md の更新以外で helper を直接編集すると FAIL するので、
helper は必ず正本を編集して `bash tools/sync-skill-scripts.sh` で同期してください。

## 設計方針

- **CLI 経由**: API 直接呼び出しではなく `codex exec` コマンドを使用
- **スキルベース**: Claude Code の Skills（`.claude/skills/`）として実装
- **外部依存ゼロ**: サプライチェーン攻撃を避けるため、npm パッケージ等は使わない。Markdown + bash/PowerShell スクリプトのみ
- **手動起動がデフォルト**: `disable-model-invocation: true`（ユーザー設定で変更可能）
- **マルチプラットフォーム**: Windows PowerShell 5.1+（Shift-JIS パス対応）と bash（Linux/macOS/WSL）の両方に対応
- **インジェクション対策**: プロンプトは stdin 経由で渡し、cmd.exe を介さない。`--` セパレータでオプション誤認を防止

## セキュリティ

- **外部依存ゼロ**: npm パッケージを使わないため、サプライチェーン攻撃のリスクがない
- **CMD インジェクション対策**: PowerShell 版は `Process.Start` で codex を直接起動し、cmd.exe やバッチファイルを経由しない。`%PATH%` や `!VAR!` などの CMD 制御文字が展開されることはない
- **プロンプトインジェクション対策**: `--` セパレータにより、プロンプト内容が codex のオプションとして解釈されることを防止
- **stdin 渡し**: プロンプトはコマンドライン引数ではなく stdin で渡すため、プロセスリストからの漏洩やコマンドライン長制限の問題がない
- **一時ファイルの自動削除**: 出力ファイル・エラーファイル・プロンプトファイルはすべてスクリプト終了時に削除
- **秘匿情報の送信に注意**: `ask-codex-with-context` はファイル内容や git diff を OpenAI に送信します。秘匿情報を含むプロジェクトでは自動呼び出し（`disable-model-invocation: false`）を避けてください

## トラブルシューティング

### `codex: command not found`

Codex CLI がインストールされていません。

```bash
npm install -g @openai/codex
```

インストール後、シェルを再起動するかパスを通してください。

### `codex login` していない / 認証エラー

```bash
codex login
```

を実行して ChatGPT アカウントでログインしてください。API キーを使う場合は環境変数を設定：

```bash
export OPENAI_API_KEY="sk-..."
```

### タイムアウト

デフォルトタイムアウトは 120 秒です。長いプロンプトや複雑な質問では足りないことがあります。ラッパーの `--timeout` / `-Timeout` オプションで延長できます。

```bash
# bash
bash scripts/codex-wrapper.sh --prompt "..." --timeout 300

# PowerShell
powershell -File scripts/codex-wrapper.ps1 -Prompt "..." -Timeout 300
```

### `timeout` コマンドが見つからない（macOS）

bash 版ラッパーは GNU coreutils の `timeout` コマンドを使います。macOS にはデフォルトで入っていません。

```bash
brew install coreutils  # gtimeout がインストールされる
```

`gtimeout` が見つかればそちらを使います。どちらも無い場合はタイムアウトなしで実行されます。

### コンテキストが大きすぎる

100KB を超えるコンテキストを渡すと警告が表示されます。大きなファイルを渡す場合は、関連部分だけを抜粋するか、`--context-file` / `-ContextFile` でファイル経由で渡してください。

### 日本語パスで WebSocket エラー

ラッパーが自動的に `-C $TEMP`（Windows）/ `-C /tmp`（Unix）を指定して回避しています。この仕組みにより、日本語パスを含むディレクトリで実行しても問題ありません。

### WSL で Windows 側の codex が使われる

WSL から実行した際に `/mnt/c/.../npm/codex` が使われてしまう場合は、WSL 内にネイティブで Codex CLI をインストールしてください。

```bash
# WSL 内で
npm install -g @openai/codex
```

## 制約事項

- ChatGPT アカウント認証の場合、使用可能モデルは codex CLI のバージョンで変わる。現行は `gpt-5.5` 等。`codex debug models` または `/list-codex-models` で確認
- 日本語パスを含む作業ディレクトリでは Codex CLI の WebSocket 接続でエラーが出るため、ラッパーで `-C` フラグにより回避
- Codex CLI の応答時間はネットワーク状況やプロンプトの複雑さに依存（デフォルトタイムアウト: 120秒）

### 回答フッターのモデル名表示について

スキルが回答末尾に表示するモデル名は、**ラッパーがモデルを解決できたときだけ** 出力されます。解決経路は `--model` フラグ → `$CODEX_WRAPPER_MODEL` → `codex-wrapper.conf` の順です（詳細は `/set-codex-model` の節参照）。どれも当てはまらなければ codex CLI のデフォルトに委任されますが、現在 `codex exec` の出力には実際に使われたモデル名が含まれない（[openai/codex#14736](https://github.com/openai/codex/issues/14736)）ため、ラッパー側でも把握できません。誤情報を出さないよう、解決できないケースではフッターでモデル名を主張しない方針です。

つまり常に正確に表示させたければ、`/set-codex-model <name>` で一度保存しておくか、`--model` を明示する運用にしてください。

## ライセンス

MIT
