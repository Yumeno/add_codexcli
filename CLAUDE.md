# CLAUDE.md

## プロジェクト概要

Claude Code から Codex CLI をセカンドオピニオンとして呼び出すスキルを開発するリポジトリ。

## 技術スタック

- Claude Code Skills（`.claude/skills/` 内の SKILL.md）
- Bash ラッパースクリプト
- Codex CLI v0.117.0+（`codex exec` による非対話実行）

## 重要な制約

- Codex CLI は ChatGPT Plus 認証では `gpt-5.2-codex` モデルのみ利用可
- 日本語パスで WebSocket エラーが出るため、`codex exec` 呼び出し時は `-C /tmp` 等で ASCII パスを指定する
- 外部パッケージは一切使わない（サプライチェーン攻撃対策）
- スキルは `disable-model-invocation: true` で手動起動のみにする
