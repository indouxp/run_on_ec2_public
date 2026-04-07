# mk-sns-topic.sh 詳細設計書

## 1. 概要

### 1.1 目的

本ドキュメントは、SNSトピック作成スクリプト `mk-sns-topic.sh` の詳細設計を定義します。

本スクリプトはSNSトピック `ts-010-sns-010` を作成します。トピックが既存の場合は削除してから再作成します。作成後はプロジェクトタグを付与します。

SNSトピックを再作成するとサブスクリプション（Email・SMS）が失われるため、完了後に手動でサブスクリプションを再設定するよう警告を出力します。

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- 命名基準書（[設計書/命名基準.md](命名基準.md)）
- 運用マニュアル（[運用マニュアル/operation-manual.md](../運用マニュアル/operation-manual.md)）

**派生文書**
- set-email-subscription.sh（サブスクリプション設定スクリプト）
- set-sms-subscription.sh（サブスクリプション設定スクリプト）

## 2. 実行環境

- **実行場所**: `infra/` ディレクトリ
- **必要コマンド**: aws cli
- **AWS認証**: `source assume-role.sh`（ts-010-role-build を AssumeRole）

## 3. 前提条件

| 条件 | 内容 |
|:---|:---|
| AWS認証 | ts-010-role-build の AssumeRole が有効であること |
| config.sh | スクリプトの実行ディレクトリに対してタグ関連変数（`PRJ_TAG_KEY`・`PRJ_TAG_VALUE`）がシェル環境に存在すること |

> **注意**: 本スクリプトは `config.sh` を明示的に `source` しません。`PRJ_TAG_KEY` と `PRJ_TAG_VALUE` は実行環境（infra/）で事前に `source config.sh` されていることを前提とします。

## 4. 入力

### 4.1 設定ファイル（config.sh）

本スクリプトは `config.sh` を直接 `source` しません。トピック名はスクリプト内にハードコードされています。タグ関連変数は実行環境から引き継がれます。

| 使用値 | 内容 | 値 |
|:---|:---|:---|
| `TOPIC_NAME` | SNSトピック名（スクリプト内定数） | `ts-010-sns-010` |
| `PRJ_TAG_KEY` | タグキー（環境変数から取得） | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | タグ値（環境変数から取得） | `ts-010` |

### 4.2 引数

なし。

## 5. 処理フロー

### 初期化処理

1. `set -euo pipefail` によるエラー時即時終了を設定する
2. 以降の標準出力・標準エラー出力を `mk-sns-topic.sh.log` にリダイレクトする
3. `TOPIC_NAME` を `ts-010-sns-010` に設定する

### confirm_topic 関数（確認）

4. `aws sns list-topics` でSNSトピック一覧を取得し、`grep "$TOPIC_NAME"` でトピックの存在確認を行う
   （存在しない場合はメッセージを出力する）

### create_topic 関数（作成処理）

5. `aws sns list-topics | grep -q "$TOPIC_NAME"` でトピックの存在確認を行う
6. トピックが既存の場合:
    - `aws sns list-topics --query 'Topics[].TopicArn' --output text | tr '\t' '\n' | grep "${TOPIC_NAME}"` でトピックARNを取得する
    - `aws sns delete-topic` で既存トピックを削除する
7. `aws sns create-topic` で新規トピックを作成し、トピックARNを `TOPIC_ARN` に格納する
8. `aws sns tag-resource` でプロジェクトタグ（`PRJ_TAG_KEY=PRJ_TAG_VALUE`）をトピックに付与する

### warn_subscriptions 関数（サブスクリプション再設定の警告）

9. トピックを再作成したためサブスクリプションが失われた旨を警告として出力する
10. 以下の手動実行コマンドを案内する
    - `set-email-subscription.sh <メールアドレス>`
    - `set-sms-subscription.sh <電話番号（例: +819012345678）>`

### メイン処理

11. `confirm_topic` でトピック作成前の状態を表示する
12. `create_topic` でSNSトピックを作成する
13. `warn_subscriptions` でサブスクリプション再設定の警告を出力する
14. `confirm_topic` でトピック作成後の状態を表示する

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| SNSトピック | `ts-010-sns-010` | 既存削除・新規作成 |
| SNSトピックタグ | `ts-010-sns-010` | プロジェクトタグ付与 |

## 7. エラーハンドリング

| 状況 | 対処 |
|:---|:---|
| `set -euo pipefail` | コマンド失敗・未定義変数参照・パイプエラー時に即時終了する |
| トピックが存在しない（`confirm_topic`） | `grep` が非マッチで非ゼロ終了するが `|| echo "..."` でエラーを吸収しメッセージを出力する |
| サブスクリプション失われ | エラーではなく警告として `warn_subscriptions` で案内する（自動再設定は不可） |

> **注意**: SNSトピックを削除すると、登録済みのすべてのサブスクリプション（Email・SMS）が失われます。再設定には `set-email-subscription.sh` および `set-sms-subscription.sh` の手動実行が必要です。

---

**作成日**: 2026年3月31日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
