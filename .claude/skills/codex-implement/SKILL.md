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
3. **実行前スナップショットの記録**: clean tree 確認の直後に `codex-verify` の
   snapshot サブコマンドを実行する。HEAD / branch / status / 保護対象ファイル
   （`.env`, `.env.*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `.git/config`, `.git/hooks`）の
   ハッシュがスナップショットファイルに記録され、後の検収（手順 5）の照合に使われる。
   呼び出しルール（素の 1 コマンド、double quote 等）は手順 3 の許可傘ブロックと同じ。
   ```bash
   powershell -ExecutionPolicy Bypass -NoProfile -File "<scripts-root>\codex-verify.ps1" -Snapshot -Repo "C:/path/to/repo"
   ```
   Linux/Mac native 環境:
   ```bash
   bash "<scripts-root>/codex-verify.sh" snapshot --repo "/path/to/repo"
   ```
   成功時は **出力の最終行に `SNAPSHOT: <path>`** が出る。この `<path>` を記録しておく
   （手順 5 の check で必須）。行頭 `[CODEX_VERIFY_ERROR]` が出た場合は snapshot 失敗
   として中断し、原因を報告する。
   **snapshot と check は同じ実装で揃える**（ps1 で取った snapshot は ps1 の check に、
   sh で取ったものは sh の check に渡す。既定の出力先パス形式が実装ごとに異なるため）。
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

#### 基本呼び出し

この SKILL.md 自身のディレクトリ直下の `scripts/` を絶対 path に解決
(通常 `$CLAUDE_SKILL_DIR/scripts/`) してから、そのパスを使う。

```bash
powershell -ExecutionPolicy Bypass -NoProfile -File "<scripts-root>\codex-wrapper.ps1" -Prompt "タスク仕様書に従って実装してください" -ContextFile "$HOME/AppData/Local/Temp/codex_ctx_p1_step1_implement_20260705-010230.txt" -Cd "C:/path/to/repo" -SandboxMode workspace-write -Timeout 600
```

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

1. `codex-verify` の check サブコマンドを、手順 1 で記録した snapshot パスを渡して実行する。
   HEAD / branch の実行前後比較、保護対象ファイルのハッシュ比較、
   `git status --porcelain=v1 --untracked-files=all` + `git diff HEAD --stat` のサマリ出力が
   この 1 コマンドで行われる（呼び出しルールは手順 3 の許可傘ブロックと同じ）:
   ```bash
   powershell -ExecutionPolicy Bypass -NoProfile -File "<scripts-root>\codex-verify.ps1" -Check -SnapshotFile "<手順1で記録したsnapshotパス>" -Repo "C:/path/to/repo"
   ```
   Linux/Mac native 環境:
   ```bash
   bash "<scripts-root>/codex-verify.sh" check --snapshot "<手順1で記録したsnapshotパス>" --repo "/path/to/repo"
   ```
2. check の出力を以下のルールで判定する
   （tool result は stdout / stderr の混合 stream なので、**どちらに出た行でも判定対象**）:
   - 行頭 `[CODEX_VERIFY_VIOLATION]` の行があれば = **Codex が禁止操作をした**
     （コミット・branch 切替・保護対象ファイルの変更等）。**最優先で警告** し、
     violation の内容に応じたロールバック案内（手順 5.6 の分岐）に進む
   - 行頭 `[CODEX_VERIFY_ERROR]` の行があれば = **検収自体が失敗**。Codex の作業結果の
     良否は判定できていないことを明示し、原因を報告する
   - 行頭 `[CODEX_VERIFY_ALLOWED]` の行は「許可済み変更」の INFO（後述の `-Allow` 使用時のみ
     出る）。違反ではないが、検収報告に必ず含める
   - どれも無ければ、出力中の status / diff サマリを使って次の照合に進む
3. Codex が応答の最後に報告した「変更ファイル一覧」と、check が出力した git の実態を
   **照合** する。**不一致なら明示的に警告する**（Codex の報告と実態の不一致の検出のため。
   例えば git 上は変更されているのに報告に無いファイルがある、逆に報告にあるのに git 上は
   無変更、など）。
4. 変更が大きい場合（目安: 10 ファイル超 or 500 行超）は diff 全文を貼らず、
   check が出力する `git diff HEAD --stat` サマリの要点のみを提示する。
5. 保護対象ファイル（`.env` 等・`.git/config`・`.git/hooks`）の確認は check が自動で行う。
   check 出力の `[CODEX_VERIFY_VIOLATION]` / `[CODEX_VERIFY_ALLOWED]` 行で結果を確認し、
   VIOLATION があれば最優先で警告する（手動での再確認は不要だが、VIOLATION/ALLOWED 行を
   報告から省略しない）。
6. 検収結果をユーザーに報告し、**検収結果に応じたロールバック手順を必ず添える**。
   基本形（unstaged の tracked 変更 + untracked のみの場合）:
   ```
   git checkout -- .
   git clean -fd
   ```
   ロールバック手順には以下の但し書き・分岐を添える:
   - 基本形で戻せるのは **unstaged の tracked 変更 + untracked ファイルのみ**
   - **staged 変更が検出された場合**（check の status サマリで検出）: `git checkout -- .` は
     index 基準で working tree を戻すため、staged 変更は破棄されない。代わりに以下を案内する
     （破壊的なのでユーザー判断で実行）:
     ```
     git restore --source=<実行前HEAD> --staged --worktree -- .
     git clean -fd
     ```
   - **HEAD のみ不一致（branch は同一）の場合**（check の VIOLATION で検出）: Codex が
     コミットした可能性がある。`git reset --hard <実行前HEAD>` を候補として提示する
     （破壊的な操作なので実行せずユーザーの判断を仰ぐ）
   - **branch も不一致の場合**（check の VIOLATION で検出）: 固定の復旧コマンドを提示しない。
     `git reset --hard <実行前HEAD>` は **現在チェックアウト中の別 branch を実行前 HEAD に
     移動させてしまい**、元 branch の復旧にならず別 branch の履歴破壊になり得る。
     まず以下の状況確認コマンドを提示し、元 branch / 現在の branch / 生成されたコミットを
     確認してから、ユーザーと個別に復旧方法を判断する:
     ```
     git branch --show-current
     git status
     git log --oneline --decorate -5
     git reflog -10
     ```
   - ignored ファイル（`.env` 等）やリポジトリ外への変更は git では戻せない

#### 保護対象ファイルの意図的な編集（`-Allow`）

タスク指示が保護対象ファイル（`.env` 等）の編集を **意図的に** 含む場合は、
**Codex 実行前（手順 2 の前）にユーザーへ明示確認** する。承認された場合のみ、
手順 5 の check に該当パターンの `-Allow` を付けて実行する:

```bash
powershell -ExecutionPolicy Bypass -NoProfile -File "<scripts-root>\codex-verify.ps1" -Check -SnapshotFile "<snapshotパス>" -Repo "C:/path/to/repo" -Allow .env
```

（bash 版は `--allow .env`。複数パターンは PowerShell 版 `-Allow p1,p2` / bash 版 `--allow p1 --allow p2`）

この場合、該当ファイルの変更は `[CODEX_VERIFY_VIOLATION]` ではなく
`[CODEX_VERIFY_ALLOWED]` 行（INFO 扱い、exit code に影響なし）として出力される。
ALLOWED 行は「ユーザー承認済みの保護対象変更」として検収報告に必ず含める。
ユーザーの事前承認なしに `-Allow` を付けてはならない。

**`-Allow` のパターンマッチ仕様**:
- パターンは **リポジトリルートからの相対パス** に対して照合する
  (例: ルート直下の `.env` は `-Allow .env`、`config/.env` は `-Allow config/.env`)
- **区切り文字は `/`** (Windows パスの `\` ではない)。両実装で統一
- **glob マッチ (case-sensitive)**。`*` は path segment 内のみマッチし、`/` は跨がない
  (例: `-Allow *.env` は直下の `foo.env` にマッチするが、`sub/foo.env` にはマッチしない)
- **サブディレクトリを含めて許可** したい場合は明示的に列挙する
  (PowerShell 版なら `-Allow ".env,config/.env"`、bash 版なら `--allow .env --allow config/.env`)
- **`-Allow *` のような過大パターンを使わない**。承認対象を最小限のパスに絞る
  (万一の想定外パスの変更が VIOLATION として上がる余地を残す設計思想)

### 6. 結果を表示する

失敗検知のフォーマットは上記「4. 失敗検知」の通り。成功時は以下のテンプレートを使う。

```
## Codex 実装結果

> タスク: (指示の要約)

### Codex の報告
(Codex の応答)

### git 検収
(codex-verify check の status / diff サマリ)
(VIOLATION / ALLOWED 行があればここに明記)
(照合結果: Codex 報告と git 実態の一致/不一致、HEAD / branch の実行前後比較)

### 次のアクション
- 内容確認後、問題なければコミットしてください
- やり直す場合: 検収結果に staged 変更やコミット・branch 切替が含まれるかで手順が
  変わるため、上記の手順 5.6 のロールバック案内（検収結果に応じて提示したもの）に従ってください

---
*via Codex CLI（モデル未指定 / codex のデフォルトに委任）*
```

モデル名フッターのルールは既存スキルと同じ:
- `-Model` を明示的に渡した場合のみ、そのモデル名を `*Model: <name> via Codex CLI*` の形式で表示する
- それ以外は上記の「モデル未指定」表記を使う。**固定のモデル名を書くのは嘘になるため絶対にしない。**
