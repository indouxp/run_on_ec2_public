# mk-s3-lifecicle.sh 詳細設計書

## 1. 概要

### 1.1 目的

本ドキュメントは、S3ライフサイクルルール作成スクリプト `mk-s3-lifecicle.sh` の詳細設計を定義します。

本スクリプトは指定されたS3バケットに対して、オブジェクトの有効期限（Expiration）ライフサイクルルールを設定します。既存のライフサイクル設定がある場合は削除してから新規作成します。主な用途はバケット内オブジェクトの自動削除による容量・コスト管理です。

### 1.2 関連文書

**参照文書**
- 構築手順書（[構築手順/構築手順書.md](../構築手順/構築手順書.md)）
- 命名基準書（[設計書/命名基準.md](命名基準.md)）
- mk-s3bkt.sh 詳細設計書（[設計書/mk-s3bkt.sh_詳細設計書.md](mk-s3bkt.sh_詳細設計書.md)）

## 2. 実行環境

- **実行場所**: `infra/` ディレクトリ
- **必要コマンド**: aws cli, python3
- **AWS認証**: `source assume-role.sh`（ts-010-role-build を AssumeRole）

## 3. 前提条件

| 条件 | 内容 |
|:---|:---|
| AWS認証 | ts-010-role-build の AssumeRole が有効であること |
| config.sh | スクリプトと同じディレクトリに `config.sh` が存在すること |
| S3バケット | 引数で指定したバケットが作成済みであること |

> **注意**: `mk-s3bkt.sh` はライフサイクルルールを自動再設定しません。S3バケットを再作成した場合は本スクリプトを手動で再実行する必要があります。

## 4. 入力

### 4.1 設定ファイル（config.sh）

`config.sh` は `source` されますが、本スクリプトの処理ではAWSリージョン等の読み込み目的であり、ライフサイクルルール設定の主要変数は引数から取得します。

| 変数名 | 説明 | 例 |
|:---|:---|:---|
| `AWS_REGION` | AWSリージョン（config.sh から読み込み） | `ap-northeast-1` |

### 4.2 引数

| 引数 | 変数名 | 説明 | 例 |
|:---|:---|:---|:---|
| 第1引数 | `BUCKET_NAME` | ライフサイクルルールを設定するS3バケット名 | `${BKT_IN}` |
| 第2引数 | `EXPIRE_DAYS` | オブジェクトを削除するまでの日数（正の整数） | `90` |

引数が不足している場合、または `EXPIRE_DAYS` が整数でない場合はUsageメッセージを出力して `exit 1` します。

## 5. 処理フロー

### 初期化処理

1. `set -euo pipefail` によるエラー時即時終了を設定する
2. `config.sh` を読み込む
3. 第1引数を `BUCKET_NAME`、第2引数を `EXPIRE_DAYS` に代入する
4. 引数が未指定（空文字）の場合はUsageメッセージを出力して `exit 1` する
5. `EXPIRE_DAYS` が正規表現 `^[0-9]+$` に一致しない場合はエラーメッセージを出力して `exit 1` する
6. 作業用一時ディレクトリ `./mk-s3-lifecicle.sh.src` を作成する
7. トラップを設定する（ERR/INT/TERM 時は一時ディレクトリ削除後に終了、EXIT 時は削除）
8. 以降の標準出力・標準エラー出力を `mk-s3-lifecicle.sh.log` にリダイレクトする
9. 現在のUTC時刻（`%Y-%m-%dT%H:%M:%SZ` 形式）を `CREATED_AT` に格納する
10. ルールID文字列 `${BUCKET_NAME}-expire-${EXPIRE_DAYS}d-created_at=${CREATED_AT}` を `RULE_ID` に設定する

### show_lifecycle 関数（ルール表示）

11. `aws s3api get-bucket-lifecycle-configuration` で対象バケットの既存ルールをJSON形式で取得する
    （ルールなしの場合は `[]` にフォールバック）
12. 取得したJSONを環境変数 `RULES_JSON` に格納し、インラインPythonスクリプトで以下を出力する
    - ルールが空の場合: 「ルールは設定されていません」を出力する
    - ルールが存在する場合: 各ルールの ID・Status・Expiration（日数または詳細）・CreatedAt（IDから抽出）を1行ずつ出力する
    - 続けてルール全体をJSON形式で出力する

### create_lifecycle 関数（ルール作成）

13. `aws s3api get-bucket-lifecycle-configuration` で既存設定の有無を確認する
14. 既存設定がある場合は `aws s3api delete-bucket-lifecycle` で削除する
15. ライフサイクル設定JSONファイル `lifecycle-${BUCKET_NAME}.json` を一時ディレクトリに生成する
    - ルールID: `RULE_ID`
    - Status: `Enabled`
    - Filter.Prefix: `""`（全オブジェクト対象）
    - Expiration.Days: `EXPIRE_DAYS`
16. `aws s3api put-bucket-lifecycle-configuration` でライフサイクル設定を適用する

### メイン処理

17. `show_lifecycle` でルール適用前の状態を表示する
18. `create_lifecycle` でライフサイクルルールを作成する
19. `show_lifecycle` でルール適用後の状態を表示する

## 6. 作成・更新リソース

| リソース種別 | リソース名 | 操作内容 |
|:---|:---|:---|
| S3ライフサイクルルール | 引数で指定したバケット | 既存設定削除・新規作成（`EXPIRE_DAYS` 日後にオブジェクト削除） |

## 7. エラーハンドリング

| 状況 | 対処 |
|:---|:---|
| 引数不足（`BUCKET_NAME` または `EXPIRE_DAYS` が空） | Usageメッセージを出力して `exit 1` |
| `EXPIRE_DAYS` が整数でない | エラーメッセージを出力して `exit 1` |
| `set -euo pipefail` | コマンド失敗・未定義変数参照・パイプエラー時に即時終了する |
| ERR/INT/TERM シグナル | `term` 関数を呼び出し、一時ディレクトリを削除後に `exit 1` |
| EXIT | `term` 関数を呼び出し、一時ディレクトリを削除する（正常終了時も含む） |
| `get-bucket-lifecycle-configuration` 失敗（ルールなし） | `2>/dev/null || echo '[]'` でエラーを吸収し `[]` にフォールバックする |

---

**作成日**: 2026年3月31日
**バージョン**: 1.0
**作成者**: tsystem
**承認者**: tsystem
