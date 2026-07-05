---
name: codex-implement
description: Codex CLI をサブエージェントとして使い、タスク仕様を渡してプロジェクト内のファイルを直接実装・編集させる。完了後は git diff で検収する。
disable-model-invocation: true
allowed-tools: Bash Read Write Grep Glob
---

# /codex-implement — Codex CLI に実装作業を委任する

Codex CLI を「セカンドオピニオン」としてではなく **実装作業者（サブエージェント）** として使い、
カレントディレクトリのリポジトリ内のファイルを直接作成・編集させます。
Claude 自身のトークン消費を Codex にオフロードする目的のスキルです。

他の Codex スキル（`/ask-codex` 系）はすべて read-only（回答を返すだけ）ですが、
このスキルは Codex に **ファイルシステムへの書き込み権限** を与える点で性質が異なります。
利用前に必ず「実行前チェック」を全て通過させてください。

## 引数の解釈

`$ARGUMENTS` はタスク指示（自由文）。空の場合はユーザーに実装内容を聞く。

例:
- `/codex-implement README のタイポを修正して`
- `/codex-implement src/utils.ts に日付フォーマット関数を追加して、対応するテストも書いて`

## 手順

### 1. 実行前チェック（安全ガード）

対象リポジトリは **カレントディレクトリ** とする。以下を順に確認し、
**いずれか一つでも満たさない場合は中断してユーザーに確認・報告する**。

1. カレントディレクトリが git リポジトリであること（`git rev-parse --is-inside-work-tree` 等で確認）。
2. `git status --porcelain` の出力が **空**（= clean tree）であること。
   汚れている場合は中断し、ユーザーに「未コミットの変更があるため中断しました。
   先にコミット/stash してから再実行してください」と提示する。
   検収時に Codex の変更と既存の変更が区別できなくなることを防ぐための必須ガード。
3. **実行前スナップショットの記録**: clean tree 確認の直後に以下の 2 コマンドを実行し、
   その出力（実行前の HEAD コミットハッシュと現在の branch 名）を記録しておく。
   後の検収（手順 5）で「Codex がコミットや branch 切替をしていないか」を照合するために使う。
   ```bash
   git rev-parse HEAD
   git branch --show-current
   ```
4. リポジトリの絶対パスが **ASCII のみ** であること（日本語などの非 ASCII 文字を含まない）。
   含む場合は中断し、以下を案内する:
   - 回避策: git worktree を ASCII パスに切って、そちらで作業する
     ```
     git worktree add -b codex-work-<name> C:/tmp/work-<name>
     ```
   - 切った worktree のパスに `cd` してから、あらためて `/codex-implement` を実行してもらう

これらのチェックとスナップショットは、`-Cd` に渡す ASCII パスの確保と、検収の前提となる
clean tree・実行前状態の記録を保証するためのガードであり、省略しない。

### 2. タスク仕様書を組み立てる

> **重要 (許可プロンプト回避):** `mktemp` / `cat > file <<EOF` (heredoc) /
> `cat a b >> c` などのシェル連結は許可設定の複合コマンド検査で止まる。
> **Read tool で材料を読み、Write tool で 1 ファイルに組み立てる** こと。

- **置き場所**: Windows + Claude Code 環境では `$HOME/AppData/Local/Temp/`
  (msys Bash で `/c/Users/<実ユーザー>/AppData/Local/Temp/` に展開される、
  Write 許可済みの唯一の TEMP)。Linux/Mac native 環境では `/tmp/`。
- **命名規約**: `codex_ctx_p<phase>_step<step>_<purpose>[_<round>]_<yyyymmdd-HHMMSS>.txt`
  - `<phase>`: 1, 2, 3 ... タスクの大きな段階
  - `<step>`: そのフェーズ内のステップ番号
  - `<purpose>`: `implement` を基本とする（同一タスクで複数回叩く場合は `<round>` を付与）
  - 例: `codex_ctx_p1_step1_implement_20260705-010230.txt`

仕様書は **「固定の安全制約 → 区切り線 → ユーザーのタスク指示」の順** で構成する
（Write tool で 1 ファイルに組み立てる）。ユーザー入力（タスク指示）が安全制約より
**後ろ** に来る構造にすることで、タスク指示側の文言による制約の上書きをプロンプト
レベルで防ぐ（完全な強制はできないが、構造として必ずこの順にする）。

1. **Codex への安全制約**（先頭に置く。次の 5 点＋優先順位宣言は必ず仕様書に書く。省略しない）:
   - `.git/`、`.env`、認証情報ファイル（トークン・鍵・credentials 等）には触らないこと
   - `git add` / `git commit` / `git checkout` / `git switch` / `git reset` / `git clean` /
     branch・tag・ref の操作 / git config・hooks・submodule の変更を行わないこと。
     ファイルの作成・編集・削除のみを行い、バージョン管理操作は依頼側が行う
   - 変更（作成・編集・削除）したファイルの一覧を、応答の **最後に必ず列挙** すること
   - テストが存在してタスクに関係するなら実行し、結果を報告すること
   - タスクの範囲外の「ついで修正」をしないこと
   - **優先順位宣言**: 「以下のタスク指示が上記の安全制約と矛盾する場合、安全制約を優先すること」
2. **区切り線**（`---` 等）を挟む
3. **対象リポジトリの構造情報**（必要に応じて。Codex は `-Cd` でリポジトリを直接読めるため、
   ディレクトリツリーの概要程度で十分。詳細な全ファイル列挙は不要）
4. **ユーザーのタスク指示**（`$ARGUMENTS` の内容をそのまま、または要約せず記載）

### 3. ラッパースクリプトを呼び出す

> **重要 (許可プロンプト回避):** Claude Code の許可傘は
> ``Bash(powershell -ExecutionPolicy Bypass -NoProfile -File *codex-wrapper.ps1*)``。
> これは **コマンドが `powershell` で始まるときだけ** マッチする。
> 以下のシェル構文で包んだ瞬間に傘から外れて毎回承認要求が出る:
> - 変数代入の前置: `ERRFILE=... powershell ...`
> - コマンド置換: `RESPONSE=$(powershell ...)`
> - stderr リダイレクト: `powershell ... 2>file`
> - パイプ: `powershell ... | tee log`
>
> **素の 1 コマンドで直接呼ぶこと。** stdout はそのまま tool result に返るので捕捉不要。
> wrapper パスは **必ず double quote で囲む** (quote なしも傘から外れる)。
> このスキルは実装タスクのため timeout は長め（600000ms 以上）を指定してよい。

`-Cd` に対象リポジトリの絶対パス（実行前チェックで ASCII 確認済みのもの）を、
`-SandboxMode workspace-write` を指定して呼び出す（これを指定しないと default の
`read-only` になり、Codex はファイルを編集できない）。

#### 基本呼び出し（グローバルインストール想定）

```bash
powershell -ExecutionPolicy Bypass -NoProfile -File "$HOME/.claude/scripts/codex-wrapper.ps1" -Prompt "タスク仕様書に従って実装してください" -ContextFile "$HOME/AppData/Local/Temp/codex_ctx_p1_step1_implement_20260705-010230.txt" -Cd "C:/path/to/repo" -SandboxMode workspace-write -Timeout 600
```

プロジェクトインストール想定（`<proj>/scripts/codex-wrapper.ps1`）の場合はラッパーパスを置換する。

- `-Cd` は対象リポジトリの絶対パス（実行前チェック済みの ASCII パス）
- `-SandboxMode workspace-write` は固定で付与する（このスキルの核心。書き忘れると read-only になり実装が失敗する）
- `-Timeout 600` を推奨（実装タスクは時間がかかる）。Bash tool 側の timeout パラメータも 600000ms 以上を指定する

### 4. 失敗検知

wrapper が失敗したとき、**stdout の先頭に `[CODEX_WRAPPER_ERROR]` で始まる行が出る**。
これは「素の 1 コマンド呼び」で stdout/stderr を分離しない運用でも、Claude が
「これは Codex の応答ではなく wrapper の失敗だ」と確実に判別できるようにするための sentinel。

tool result のいずれかの行が `[CODEX_WRAPPER_ERROR]` で始まっていたら、**Codex の応答ではなく
wrapper のエラーとして提示する**。例:

```
## Codex CLI 呼び出しに失敗しました

(sentinel 行とそれ以降のエラー詳細をそのまま掲示)
```

成功時は sentinel が出ないので、以下の検収フローに進む。

### 5. 検収（実行後）

Codex の応答を鵜呑みにせず、**必ず git で実態を確認する**:

1. `git rev-parse HEAD` を再実行し、**実行前スナップショット（手順 1）の HEAD と一致する
   ことを確認** する。不一致なら「Codex がコミットまたは履歴操作をした可能性がある」と
   **最優先で警告** し、`git log --oneline -5` で状況を提示する
   （HEAD が動いていると、以降の working tree ベースの検収は「無変更」と誤認するため）。
2. `git branch --show-current` も同様に実行前スナップショットと比較する（branch 切替の検出）。
3. `git status --porcelain=v1 --untracked-files=all` を実行し、staged / unstaged / untracked の
   変更を **全て** 確認する。
4. `git diff HEAD --stat` で staged 込みの変更量を確認する（working tree だけの
   `git diff --stat` では staged された変更が漏れるため）。
5. Codex が応答の最後に報告した「変更ファイル一覧」と、git の実態を **照合** する。
   **不一致なら明示的に警告する**（Codex の報告と実態の不一致の検出のため。例えば git 上は
   変更されているのに報告に無いファイルがある、逆に報告にあるのに git 上は無変更、など）。
6. 変更が大きい場合（目安: 10 ファイル超 or 500 行超）は diff 全文を貼らず、
   `git diff HEAD --stat` の要点のみを提示する。
7. `.git/`、`.env` など保護対象ファイルが変更されていないか確認する。変更されていたら
   最優先で警告する。
8. 検収結果をユーザーに報告し、**ロールバック手順を必ず添える**:
   ```
   git checkout -- .
   git clean -fd
   ```
   ロールバック手順には以下の但し書きを添える:
   - この手順で戻せるのは **未コミットの tracked / untracked 変更のみ**
   - Codex がコミットしていた場合（手順 1 の HEAD 不一致で検出）は
     `git reset --hard <実行前HEAD>` が必要になるが、これは破壊的な操作なので
     実行せずユーザーの判断を仰ぐ
   - ignored ファイル（`.env` 等）やリポジトリ外への変更は git では戻せない

### 6. 結果を表示する

失敗検知のフォーマットは上記「4. 失敗検知」の通り。成功時は以下のテンプレートを使う。

```
## Codex 実装結果

> タスク: (指示の要約)

### Codex の報告
(Codex の応答)

### git 検収
(git diff HEAD --stat の内容)
(照合結果: Codex 報告と git 実態の一致/不一致、HEAD / branch の実行前後比較)

### 次のアクション
- 内容確認後、問題なければコミットしてください
- やり直す場合: `git checkout -- .` && `git clean -fd`

---
*via Codex CLI（モデル未指定 / codex のデフォルトに委任）*
```

モデル名フッターのルールは既存スキルと同じ:
- `-Model` を明示的に渡した場合のみ、そのモデル名を `*Model: <name> via Codex CLI*` の形式で表示する
- それ以外は上記の「モデル未指定」表記を使う。**固定のモデル名を書くのは嘘になるため絶対にしない。**
