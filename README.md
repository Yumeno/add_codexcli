# add_codexcli

Claude Code から OpenAI Codex CLI にセカンドオピニオンを求めるためのスキル。

## 概要

Claude Code での作業中に、Codex CLI（gpt-5.2-codex）へ質問・監査・レビューを依頼できるカスタムスキルを提供します。

- `/ask-codex` — 質問テキストを Codex に投げてセカンドオピニオンを得る
- `/ask-codex-with-context` — 現在のファイルや git diff を添えて Codex に渡す

## 前提条件

- [Claude Code](https://claude.ai/code) がインストール済み
- [Codex CLI](https://github.com/openai/codex) がインストール済み（`npm install -g @openai/codex`）
- ChatGPT Plus/Pro アカウントで `codex login` 済み、または `OPENAI_API_KEY` 環境変数を設定済み

## 設計方針

- **CLI 経由**: API 直接呼び出しではなく `codex exec` コマンドを使用
- **スキルベース**: Claude Code の Skills（`.claude/skills/`）として実装
- **外部依存ゼロ**: サプライチェーン攻撃を避けるため、npm パッケージ等は使わない。Markdown + bash スクリプトのみ
- **手動起動のみ**: コスト管理のため `disable-model-invocation: true`（Claude が勝手に呼ばない）

## 制約事項

- ChatGPT アカウント認証の場合、使用可能モデルは `gpt-5.2-codex` のみ
- 日本語パスを含む作業ディレクトリでは Codex CLI の WebSocket 接続でエラーが出るため、ラッパーで `-C` フラグにより回避
