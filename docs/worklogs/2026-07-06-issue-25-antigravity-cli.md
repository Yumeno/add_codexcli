# Issue #25: Antigravity CLI向けSkillインストール対応

- 作業日: 2026-07-06
- 対象Issue: [#25 Antigravity CLI向けのSkillインストール方法を追加する](https://github.com/Yumeno/add_codexcli/issues/25)
- 参考実装: [Yumeno/add_claudecode](https://github.com/Yumeno/add_claudecode)
- 状態: 実装済み、代表Skillの実機呼び出し確認済み

## 目的

既存の5つのCodex連携Skillを、Claude Codeに加えてAntigravity CLIからも利用できるようにする。
既存のClaude Code向け導入を壊さず、Skill定義の二重管理と設定ファイルの意図しない分裂を避ける。

## 設計判断

### ホスト別にSkillの正本を分離

当初は`.claude/skills`を正本とし、pathと`$ARGUMENTS`だけを変換する方式を実装した。
しかしAntigravity CLI実機では、Claude固有の許可傘、tool名、長い運用手順が判断を阻害し、
Skillファイルを読んでもwrapper実行へ到達しなかった。

実機結果に基づき、正本をホスト別に分離した。

- Claude Code: `.claude/skills`
- Antigravity CLI: `.agents/skills`

Antigravity版は同じ機能と安全原則を保ちつつ、Antigravityのpermissionとtool実行に合わせて
簡潔に記述した。インストール時の変換は`{{SCRIPTS_ROOT}}`だけに限定した。

### 配置先

公式のAntigravity CLI向け資料に基づき、既定値を次のとおりとした。

- グローバルSkill: `~/.gemini/antigravity-cli/skills/`
- グローバルscripts: `~/.gemini/scripts/`
- プロジェクトSkill: `<project>/.agents/skills/`
- プロジェクトscripts: `<project>/scripts/`

確認したローカルAntigravity CLIのバージョンは`1.0.16`。

### 更新対象のallowlist

インストーラーは次の対象だけを更新する。

Skill:

- `ask-codex`
- `ask-codex-with-context`
- `codex-implement`
- `list-codex-models`
- `set-codex-model`

scripts:

- `codex-wrapper.ps1`
- `codex-wrapper.sh`
- `codex-verify.ps1`
- `codex-verify.sh`
- `list-codex-models.ps1`
- `list-codex-models.sh`

配置先にある無関係なSkillやファイルは削除しない。同名の管理対象Skillはstaging後に入れ替える。
`codex-wrapper.conf`はコピー対象に含めず、配置先のwrapperと同じディレクトリで生成・維持する。

### permission境界

Claude Codeの許可傘をAntigravity CLIへ自動移植しない。Antigravity CLI側では
`command(...)`単位のpermission確認に従う。インストーラーは
`--dangerously-skip-permissions`を設定しない。

## 変更内容

- `scripts/install-for-antigravity.ps1`
  - Windows PowerShell 5.1+向けインストーラー
  - UTF-8 BOM
  - 配置先とscripts配置先を引数で変更可能
- `scripts/install-for-antigravity.sh`
  - Linux、macOS、WSL向けインストーラー
  - PowerShell版と同じ5 Skill、6 scriptsを対象
- `scripts/tests/test-install-antigravity.ps1`
  - 日本語・スペースを含むpathで検証
  - 既存Skill保持、同名更新、再実行、cleanup、BOMを検証
- `scripts/tests/test-install-antigravity.sh`
  - bash版の同等契約を検証するテスト
- `README.md`
  - 対応ホスト、配置先、導入、更新、アンインストール、permission差異を追記
- `.agents/skills/*/SKILL.md`
  - Antigravity CLI専用の5 Skill
  - Claude Code固有の許可傘や`$ARGUMENTS`へ依存しない

## 検証結果

### 成功

`powershell -ExecutionPolicy Bypass -NoProfile -File scripts/tests/test-install-antigravity.ps1`

- 7件成功、0件失敗
- 5 Skillの配置
- scripts allowlist
- `{{SCRIPTS_ROOT}}` placeholderの解決
- 無関係なSkillの保持
- 同名Skillの置換
- 再実行可能性
- staging directoryのcleanup
- PowerShellファイルのUTF-8 BOM

全PowerShellファイルを`System.Management.Automation.Language.Parser`で解析し、構文エラーなし。

`scripts/tests/test-verify.ps1`は25件成功、0件失敗。

### 既存テストの環境依存失敗

`scripts/tests/test-wrapper.ps1`は43件中40件成功。3件は、この環境で`codex`がPATHから
解決できないため失敗した。今回変更したインストーラー経路とは無関係。

`scripts/tests/test-list-models.ps1`は3件とも、同じく`codex CLI not found in PATH`で失敗した。

### Antigravity CLI実機テスト

Antigravity CLI `1.0.16`、Windows 11で実施した。

当初のClaude Skill変換版:

- 最初の`agy --sandbox` probeはGo runtimeの`cannot allocate memory`で起動前に失敗
- `--sandbox`を外した一覧探索promptは長時間の探索ループとなり、Codexホスト側のセッションも中断
- workspace配置、グローバル配置ともSkillファイルの読込までは到達
- wrapperを実行せず探索を継続し、45～60秒でtimeout
- この結果を受け、`.agents/skills`へ専用Skillを実装

修正後:

1. `~/.gemini/antigravity-cli/skills/`へ5 Skillをインストール
2. `~/.gemini/scripts/`へ6 scriptsをインストール
3. 次を実行
   ```text
   agy --print-timeout 45s --print "/ask-codex 1+1の答えを数字だけで返してください"
   ```
4. 18.6秒、終了コード0で次の応答を確認
   ```text
   I am running the Codex command to get the answer. I will provide the result once the command finishes execution.
   2

   *via Codex CLI*
   ```

これにより、代表Skill`ask-codex`の認識、Skill手順の実行、Codex回答の返却を確認した。

実機テスト後の状態:

- 5 Skillは`~/.gemini/antigravity-cli/skills/`へインストール済み
- 6 scriptsは`~/.gemini/scripts/`へインストール済み
- `C:\tmp\add-codexcli-agy-smoke`の一時workspaceと診断ログは削除済み

### 未実行

- bashテスト
  - このWindows環境では`bash.exe`が未導入WSLのランチャーで、Git Bashも存在しないため未実行。

## 残課題

1. Linux、macOS、WSLまたはGit Bashで`test-install-antigravity.sh`を実行する。
2. 残り4 Skillは必要になった時点で各系統1件ずつ段階的に実機確認する。

## 参照資料

- [Antigravity CLI: Plugins & skills](https://antigravity.google/docs/cli-plugins)
- [Antigravity CLI: Gemini CLI migration](https://antigravity.google/docs/gcli-migration)
- [add_claudecode Issue #2](https://github.com/Yumeno/add_claudecode/issues/2)
- [add_claudecode Antigravity対応コミット](https://github.com/Yumeno/add_claudecode/commit/529af65511b5ca42785365d50fa33ea4bb43a2ca)
