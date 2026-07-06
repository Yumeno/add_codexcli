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

| ホストCLI | Skillの配置先 | 共通scriptsの配置先 | 状態 |
|---|---|---|---|
| Claude Code | `.claude/skills/` または `~/.claude/skills/` | `<project>/scripts/` または `~/.claude/scripts/` | 対応済み |
| Antigravity CLI | `<project>/.agents/skills/` または `~/.gemini/antigravity-cli/skills/` | `<project>/scripts/` または `~/.gemini/scripts/` | 対応済み |

Claude Code用の正本は`.claude/skills/`、Antigravity CLI用の正本は`.agents/skills/`です。
両ホストではtool名、permission、引数の扱いが異なるため、安全境界を混在させません。
Antigravity CLI向けインストーラーは、`.agents/skills/`内のscripts path placeholderだけを
実際のインストール先へ置換します。

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

既定の配置先:

- skills: `~/.gemini/antigravity-cli/skills/`
- scripts: `~/.gemini/scripts/`
- モデル設定: `~/.gemini/scripts/codex-wrapper.conf`

別の場所へインストールする場合:

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File scripts/install-for-antigravity.ps1 `
  -DestinationRoot "C:\path\to\antigravity-cli" `
  -ScriptsRoot "C:\path\to\shared-scripts"
```

```bash
bash scripts/install-for-antigravity.sh \
  "/path/to/antigravity-cli" \
  "/path/to/shared-scripts"
```

プロジェクトローカルへ配置する場合は、プロジェクトルートで次のように指定します。

```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File scripts/install-for-antigravity.ps1 `
  -DestinationRoot (Join-Path (Get-Location) ".agents") `
  -ScriptsRoot (Join-Path (Get-Location) "scripts")
```

```bash
bash scripts/install-for-antigravity.sh "$PWD/.agents" "$PWD/scripts"
```

再実行すると、このリポジトリが管理する同名5 Skillと6 scriptsだけを更新します。
ほかのSkillは削除しません。アンインストール時は、配置先から次の5ディレクトリと
6ファイルだけを削除してください。

- skills: `ask-codex`、`ask-codex-with-context`、`codex-implement`、
  `list-codex-models`、`set-codex-model`
- scripts: `codex-wrapper.ps1`、`codex-wrapper.sh`、`codex-verify.ps1`、
  `codex-verify.sh`、`list-codex-models.ps1`、`list-codex-models.sh`

インストール後にAntigravity CLIを再起動すると、5 Skillがslash commandとして自動importされます。
現行CLIにはSkill一覧専用のサブコマンドがないため、TUIで`/ask-codex`等を入力して認識を確認します。
CLIのバージョンにより探索先が異なる場合は、`DestinationRoot`を明示して再インストールしてください。

Antigravity CLIのpermission設定はClaude Codeの許可傘とは別管理です。初回のwrapper実行時に
`command(...)`の承認が求められる場合は、表示された実コマンドを確認して許可してください。
Claude Code用の許可設定をAntigravityへ自動移植したり、`--dangerously-skip-permissions`を
有効化したりはしません。

### 方法 1: 新規プロジェクトとしてクローン（最も簡単）

```bash
git clone https://github.com/Yumeno/add_codexcli.git
cd add_codexcli
```

Claude Code をこのディレクトリで開けば、すぐに `/ask-codex` が使えます。

### 方法 2: 既存プロジェクトにスキルだけ追加

既存のリポジトリに `.claude/skills/` がまだない場合：

```bash
cd /path/to/your-project

# スキルファイルをコピー
mkdir -p .claude/skills/ask-codex .claude/skills/ask-codex-with-context
curl -sL https://raw.githubusercontent.com/Yumeno/add_codexcli/main/.claude/skills/ask-codex/SKILL.md \
  -o .claude/skills/ask-codex/SKILL.md
curl -sL https://raw.githubusercontent.com/Yumeno/add_codexcli/main/.claude/skills/ask-codex-with-context/SKILL.md \
  -o .claude/skills/ask-codex-with-context/SKILL.md

# ラッパースクリプトをコピー
mkdir -p scripts
curl -sL https://raw.githubusercontent.com/Yumeno/add_codexcli/main/scripts/codex-wrapper.ps1 \
  -o scripts/codex-wrapper.ps1
curl -sL https://raw.githubusercontent.com/Yumeno/add_codexcli/main/scripts/codex-wrapper.sh \
  -o scripts/codex-wrapper.sh
chmod +x scripts/codex-wrapper.sh
```

> **注意:** SKILL.md 内のラッパーパスは `${CLAUDE_SKILL_DIR}/../../../scripts/` を参照しています。スキルとスクリプトのディレクトリ構造を変える場合は、SKILL.md 内のパスも合わせて修正してください。

### 方法 3: 既存の .claude/skills/ に追加（既にスキルがある場合）

既に `.claude/skills/` にほかのスキルがある場合でも、ディレクトリを追加するだけです。既存スキルとは干渉しません。

```bash
cd /path/to/your-project

# 既存のスキルはそのまま。新しいディレクトリを追加するだけ
ls .claude/skills/
# => my-existing-skill/  another-skill/  ← 既存のまま

# ask-codex スキルを追加
mkdir -p .claude/skills/ask-codex .claude/skills/ask-codex-with-context
# (方法2と同じ curl コマンドで SKILL.md をダウンロード)
```

### 方法 4: 個人スキルとしてグローバルインストール

特定のプロジェクトではなく、すべてのプロジェクトで使いたい場合：

**Linux / macOS / WSL / Git Bash:**

```bash
# グローバルスキルディレクトリに配置
mkdir -p ~/.claude/skills/ask-codex ~/.claude/skills/ask-codex-with-context

# SKILL.md をコピー
curl -sL https://raw.githubusercontent.com/Yumeno/add_codexcli/main/.claude/skills/ask-codex/SKILL.md \
  -o ~/.claude/skills/ask-codex/SKILL.md
curl -sL https://raw.githubusercontent.com/Yumeno/add_codexcli/main/.claude/skills/ask-codex-with-context/SKILL.md \
  -o ~/.claude/skills/ask-codex-with-context/SKILL.md

# ラッパースクリプトは固定パスに置く
mkdir -p ~/.claude/scripts
curl -sL https://raw.githubusercontent.com/Yumeno/add_codexcli/main/scripts/codex-wrapper.ps1 \
  -o ~/.claude/scripts/codex-wrapper.ps1
curl -sL https://raw.githubusercontent.com/Yumeno/add_codexcli/main/scripts/codex-wrapper.sh \
  -o ~/.claude/scripts/codex-wrapper.sh
chmod +x ~/.claude/scripts/codex-wrapper.sh
```

**Windows (PowerShell):**

```powershell
# グローバルスキルディレクトリに配置
$ClaudeDir = "$env:USERPROFILE\.claude"
New-Item -ItemType Directory -Force -Path "$ClaudeDir\skills\ask-codex", "$ClaudeDir\skills\ask-codex-with-context", "$ClaudeDir\scripts"

# SKILL.md をダウンロード
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Yumeno/add_codexcli/main/.claude/skills/ask-codex/SKILL.md" `
  -OutFile "$ClaudeDir\skills\ask-codex\SKILL.md"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Yumeno/add_codexcli/main/.claude/skills/ask-codex-with-context/SKILL.md" `
  -OutFile "$ClaudeDir\skills\ask-codex-with-context\SKILL.md"

# ラッパースクリプトをダウンロード
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Yumeno/add_codexcli/main/scripts/codex-wrapper.ps1" `
  -OutFile "$ClaudeDir\scripts\codex-wrapper.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Yumeno/add_codexcli/main/scripts/codex-wrapper.sh" `
  -OutFile "$ClaudeDir\scripts\codex-wrapper.sh"
```

> **重要:** グローバルインストールの場合、SKILL.md 内のラッパーパスを書き換える必要があります。
> - Linux/macOS/WSL: `~/.claude/scripts/codex-wrapper.sh`
> - Windows: `%USERPROFILE%\.claude\scripts\codex-wrapper.ps1`（または `$env:USERPROFILE\.claude\scripts\codex-wrapper.ps1`）

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

設定ファイルは **ラッパースクリプトと同じディレクトリ** に置かれます。プロジェクト構成・グローバル構成のどちらでも相対位置が同じになるため、SKILL.md やスクリプトを編集する必要はありません:

| インストール方法 | 設定ファイルの場所 |
|---|---|
| プロジェクト | `<proj>/scripts/codex-wrapper.conf` |
| グローバル | `~/.claude/scripts/codex-wrapper.conf` |

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

```
.claude/skills/
├── ask-codex/SKILL.md                 # /ask-codex スキル定義
├── ask-codex-with-context/SKILL.md    # /ask-codex-with-context スキル定義
├── codex-implement/SKILL.md           # /codex-implement スキル定義
├── list-codex-models/SKILL.md         # /list-codex-models スキル定義
└── set-codex-model/SKILL.md           # /set-codex-model スキル定義

scripts/
├── codex-wrapper.ps1                  # Windows PowerShell 用ラッパー
├── codex-wrapper.sh                   # bash 用ラッパー（Linux/macOS/WSL）
├── codex-wrapper.conf                 # （自動生成）デフォルトモデル設定。 .gitignore 対象
├── codex-verify.ps1                   # /codex-implement 用 検収ヘルパー（PowerShell）
├── codex-verify.sh                    # /codex-implement 用 検収ヘルパー（bash）
├── list-codex-models.ps1              # 利用可能モデル一覧ヘルパー（PowerShell）
├── list-codex-models.sh               # 利用可能モデル一覧ヘルパー（bash）
└── tests/
    ├── test-wrapper.ps1               # PowerShell 版ユニットテスト
    ├── test-wrapper.sh                # bash 版ユニットテスト
    ├── test-verify.ps1                # codex-verify.ps1 のテスト
    ├── test-verify.sh                 # codex-verify.sh のテスト
    ├── test-list-models.ps1           # list-codex-models.ps1 のテスト
    ├── test-list-models.sh            # list-codex-models.sh のテスト
    ├── test-install-antigravity.ps1   # Antigravity CLIインストーラーのテスト
    ├── test-install-antigravity.sh    # Antigravity CLIインストーラーのテスト
    └── test-e2e.sh                    # E2E テスト
```

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
powershell -ExecutionPolicy Bypass -File scripts/tests/test-install-antigravity.ps1

# bash 版（Linux/macOS/WSL/Git Bash）
bash scripts/tests/test-wrapper.sh
bash scripts/tests/test-verify.sh
bash scripts/tests/test-list-models.sh
bash scripts/tests/test-install-antigravity.sh

# E2E テスト
bash scripts/tests/test-e2e.sh
```

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
