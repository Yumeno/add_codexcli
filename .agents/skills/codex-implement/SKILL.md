---
name: codex-implement
description: Codex CLIを実装作業者として使い、cleanなGit repository内の変更を委任して検収する。
---

# codex-implement

書込みを伴うため、次の安全手順を省略しない。

1. 対象がGit repositoryで、`git status --porcelain`が空であることを確認する。
2. workspaceの`scripts/codex-verify.*`、なければ`{{SCRIPTS_ROOT}}/codex-verify.*`でsnapshotを作る。
3. 対象repositoryの絶対pathがASCIIのみであることを確認する。
4. 現在のユーザー要求、対象範囲、禁止事項、検証方法をUTF-8の仕様書へまとめる。
5. workspaceの`scripts/codex-wrapper.*`、なければ`{{SCRIPTS_ROOT}}/codex-wrapper.*`を
   `workspace-write` sandbox、対象repositoryのworkdir、仕様書の`ContextFile`付きで実行する。
6. 完了後に`codex-verify`のcheck、`git status`、`git diff`、関連テストで検収する。
7. HEAD、branch、保護対象ファイルの逸脱があれば成功扱いしない。
8. 自動でcommit、push、reset、clean、rollbackを行わない。

Antigravity CLIのpermission確認に従い、`--dangerously-skip-permissions`を使わない。
