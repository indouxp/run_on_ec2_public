# set-cloud-trail.sh 詳細設計書

## 1. 概要

### 1.1 目的

本スクリプトは、S3 データイベントを記録する CloudTrail 証跡（`ts-010-trail-010`）を作成します。ログは専用 S3 バケット（`${BKT_CLOUDTRAIL}`）に保存します。既存の同名証跡が存在する場合は削除してから再作成します。

作成するリソース:
- S3 バケット（名前: `${BKT_CLOUDTRAIL}`）
  - バケットポリシー: CloudTrail サービスによる GetBucketAcl・PutObject を許可
- CloudTrail 証跡（名前: `ts-010-trail-010`）
  - マルチリージョン証跡
  - グローバルサービスイベントを含む
  - データイベント: S3 全オブジェクト（読み書き両方）
  - 管理イベントを含む
- 証跡のロギング開始

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- 命名基準書（[設計書/命名基準.md](命名基準.md)）

**派生文書**
- なし

---

## 2. 実行環境

- 実行場所: `infra/` ディレクトリ
- 必要コマンド: aws cli
- AWS 認証: `source assume-role.sh`（`ts-010-role-build` を AssumeRole）

---

## 3. 前提条件

特になし（本スクリプトは S3 バケットも自動作成します）。

---

## 4. 入力

### 4.1 設定ファイル（config.sh）

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `PRJ_PREFIX` | プロジェクトプレフィックス | `ts-010` |
| `AWS_REGION` | AWSリージョン | `ap-northeast-1` |
| `PRJ_TAG_KEY` | プロジェクト識別用タグキー | `PRJ_NAME` |
| `PRJ_TAG_VALUE` | プロジェクト識別用タグ値 | `ts-010` |

### 4.2 スクリプト内固定値

| 変数名 | 内容 | 値 |
|:---|:---|:---|
| `TRAIL_NAME` | 証跡名 | `ts-010-trail-010` |
| `TRAIL_LOG_BKT_NAME` | ログ用 S3 バケット名 | `${BKT_CLOUDTRAIL}` |

### 4.3 引数

コマンドライン引数はありません。

---

## 5. 処理フロー

### 初期化

1. `config.sh` を読み込み、環境変数を設定する。
2. ログファイル（`set-cloud-trail.sh.log`）へのリダイレクトを設定する（`exec >> LOG_PATH 2>&1`）。

> 注意: 本スクリプトは `MY_SRC_DIR`（作業用一時ディレクトリ）を使用しません。

### `confirm_trail()` — 実行前後の確認

3. `aws cloudtrail get-trail` で証跡の存在と設定を表示する（存在しない場合はその旨を表示）。
4. `aws cloudtrail get-event-selectors` でイベントセレクター設定を表示する。
5. `aws s3api head-bucket` でログ用 S3 バケットの存在を確認する。

### `make_trail()` — 証跡作成処理

6. 既存の証跡が存在する場合: `aws cloudtrail delete-trail` で削除する。
7. ログ用 S3 バケットが存在しない場合:
   a. `aws s3api create-bucket` でバケットを作成する（`--create-bucket-configuration LocationConstraint` でリージョン指定）。
   b. `aws s3api put-bucket-tagging` でプロジェクトタグを付与する。
   c. バケットポリシー JSON を生成する:
      - Statement 1: CloudTrail が `s3:GetBucketAcl` を実行できる権限
      - Statement 2: CloudTrail が `s3:PutObject` を実行できる権限（バケット所有者フルコントロール条件付き）
   d. `aws s3api put-bucket-policy` でバケットポリシーを設定する。
8. `aws cloudtrail create-trail` で証跡を作成する:
   - S3 バケット: `${BKT_CLOUDTRAIL}`
   - `--is-multi-region-trail`（マルチリージョン）
   - `--include-global-service-events`（グローバルサービスイベント含む）
9. イベントセレクター JSON を生成する:
   - ReadWriteType: `All`
   - IncludeManagementEvents: `true`
   - DataResources: S3 全オブジェクト（`arn:aws:s3:::`）
10. `aws cloudtrail put-event-selectors` でイベントセレクターを設定する。
11. `aws cloudtrail get-trail` で証跡の ARN を取得する。
12. `aws cloudtrail add-tags` で証跡にプロジェクトタグを付与する。
13. `aws cloudtrail start-logging` で証跡のロギングを開始する。

### メイン処理の流れ

14. 実行前に `confirm_trail()` を呼び出してリソース状態を記録する。
15. `make_trail()` を呼び出してリソースを作成する。
16. 実行後に `confirm_trail()` を再度呼び出して結果を確認する。

---

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| S3 バケット | `${BKT_CLOUDTRAIL}` | 存在しない場合のみ新規作成 |
| S3 バケットポリシー | `${BKT_CLOUDTRAIL}` | CloudTrail 用ポリシー設定 |
| CloudTrail 証跡 | `ts-010-trail-010` | 既存削除→新規作成（マルチリージョン） |

---

## 7. エラーハンドリング

- スクリプト先頭に `set -euo pipefail` を設定し、コマンド失敗・未定義変数参照・パイプエラーで即時終了する。
- 既存証跡の確認・削除は `2>/dev/null` でエラー出力を抑制する。
- ログ用 S3 バケットはべき等処理（既に存在する場合は作成をスキップ）。
- すべての処理ログは `set-cloud-trail.sh.log` に記録される。

---

**作成日**: 2026年4月1日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
