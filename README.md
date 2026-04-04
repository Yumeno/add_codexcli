# add_codexcli

Claude Code から OpenAI Codex CLI にセカンドオピニオンを求めるためのスキル。

## 概要

Claude Code での作業中に、Codex CLI（gpt-5.2-codex）へ質問・監査・レビューを依頼できるカスタムスキルを提供します。

- **`/ask-codex`** — 質問テキストを Codex に投げてセカンドオピニオンを得る
- **`/ask-codex-with-context`** — 現在のファイルや git diff を添えて Codex に渡す

## 前提条件

- [Claude Code](https://claude.ai/code)（CLI / Desktop / Web いずれか）
- [Codex CLI](https://github.com/openai/codex) v0.117.0 以上
  ```bash
  npm install -g @openai/codex
  ```
- ChatGPT Plus/Pro アカウントで `codex login` 済み、または `OPENAI_API_KEY` 環境変数を設定済み

## インストール

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
mkdir -p scripts/tests
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

```bash
# グローバルスキルディレクトリに配置
mkdir -p ~/.claude/skills/ask-codex ~/.claude/skills/ask-codex-with-context

# SKILL.md をコピー（curl or 手動コピー）
curl -sL https://raw.githubusercontent.com/Yumeno/add_codexcli/main/.claude/skills/ask-codex/SKILL.md \
  -o ~/.claude/skills/ask-codex/SKILL.md
curl -sL https://raw.githubusercontent.com/Yumeno/add_codexcli/main/.claude/skills/ask-codex-with-context/SKILL.md \
  -o ~/.claude/skills/ask-codex-with-context/SKILL.md

# ラッパースクリプトは固定パスに置く（例: ~/.claude/scripts/）
mkdir -p ~/.claude/scripts
curl -sL https://raw.githubusercontent.com/Yumeno/add_codexcli/main/scripts/codex-wrapper.ps1 \
  -o ~/.claude/scripts/codex-wrapper.ps1
curl -sL https://raw.githubusercontent.com/Yumeno/add_codexcli/main/scripts/codex-wrapper.sh \
  -o ~/.claude/scripts/codex-wrapper.sh
chmod +x ~/.claude/scripts/codex-wrapper.sh
```

> **重要:** グローバルインストールの場合、SKILL.md 内のラッパーパスを `~/.claude/scripts/codex-wrapper.sh` に書き換える必要があります。

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
└── ask-codex-with-context/SKILL.md    # /ask-codex-with-context スキル定義

scripts/
├── codex-wrapper.ps1                  # Windows PowerShell 用ラッパー
├── codex-wrapper.sh                   # bash 用ラッパー（Linux/macOS/WSL）
└── tests/
    ├── test-wrapper.ps1               # PowerShell 版ユニットテスト
    ├── test-wrapper.sh                # bash 版ユニットテスト
    └── test-e2e.sh                    # E2E テスト
```

## テスト

```bash
# PowerShell 版（Windows）
powershell -ExecutionPolicy Bypass -File scripts/tests/test-wrapper.ps1

# bash 版（Linux/macOS/WSL/Git Bash）
bash scripts/tests/test-wrapper.sh

# E2E テスト
bash scripts/tests/test-e2e.sh
```

## 設計方針

- **CLI 経由**: API 直接呼び出しではなく `codex exec` コマンドを使用
- **スキルベース**: Claude Code の Skills（`.claude/skills/`）として実装
- **外部依存ゼロ**: サプライチェーン攻撃を避けるため、npm パッケージ等は使わない。Markdown + bash/PowerShell スクリプトのみ
- **手動起動のみ**: コスト管理のため `disable-model-invocation: true`（Claude が勝手に呼ばない）
- **マルチプラットフォーム**: Windows PowerShell（Shift-JIS パス対応）と bash（Linux/macOS/WSL）の両方に対応

## トラブルシューティング

### `codex: command not found`

Codex CLI がインストールされていません。

```bash
npm install -g @openai/codex
```

インストール後、シェルを再起動するかパスを通してください。

### `Error: stdin is not a terminal`

PowerShell の `Start-Job` 内で codex を呼ぶと発生します。ラッパースクリプトの最新版では `cmd.exe` 経由で実行するため、この問題は解消済みです。ラッパーを最新版に更新してください。

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

100KB を超えるコンテキストを渡すと警告が表示されます。大きなファイルを渡す場合は、関連部分だけを抜粋するか、`--context-file` / `-ContextFile` でファイル経由で渡してください（コマンドライン長制限を回避）。

### 日本語パスで WebSocket エラー

ラッパーが自動的に `-C $TEMP`（Windows）/ `-C /tmp`（Unix）を指定して回避しています。この仕組みにより、日本語パスを含むディレクトリで実行しても問題ありません。

## 制約事項

- ChatGPT アカウント認証の場合、使用可能モデルは `gpt-5.2-codex` のみ
- 日本語パスを含む作業ディレクトリでは Codex CLI の WebSocket 接続でエラーが出るため、ラッパーで `-C` フラグにより回避
- Codex CLI の応答時間はネットワーク状況やプロンプトの複雑さに依存（デフォルトタイムアウト: 120秒）
