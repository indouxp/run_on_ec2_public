#!/usr/bin/env bash
################################################################################
# スクリプト名 : mk-infra.sh
# 概要         : infra/ ディレクトリを作成し、src/shell/ の各スクリプトへの
#                シンボリックリンクを設置する
#                infra/ はインフラ構築スクリプトの実行作業ディレクトリ
# 使用方法     : bash src/shell/mk-infra.sh  （プロジェクトルートから実行）
#                または src/shell/ から ./mk-infra.sh
# Created      : 2026-03-19
# Last updated: 2026-03-26 20:41:26
# Author       : Tsystem
# 更新履歴     :
#    2026-03-19: 初版
#    2026-03-26: aws-*.sh / info-all.sh / reissue-accesskey.sh / 構築手順書.md を追加
################################################################################
set -euo pipefail

# スクリプト自身の場所からプロジェクトルートを算出
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)   # src/shell/
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)  # プロジェクトルート

# infra/ ディレクトリパス
INFRA_DIR="${PROJECT_ROOT}/infra"

# src/shell/ から infra/ への相対パス（シンボリックリンクのリンク先に使用）
REL_SHELL="../src/shell"

echo "プロジェクトルート : ${PROJECT_ROOT}"
echo "infra ディレクトリ : ${INFRA_DIR}"

################################################################################
# infra/ ディレクトリ作成
################################################################################
mkdir -p "${INFRA_DIR}"
echo "作成: ${INFRA_DIR}"

################################################################################
# シンボリックリンクの作成
# infra/ 内のリンクから src/shell/ への相対パスでリンクを張る
################################################################################
cd "${INFRA_DIR}"

# mk-*.sh
for f in "${SCRIPT_DIR}"/mk-*.sh; do
  name=$(basename "$f")
  ln -sf "${REL_SHELL}/${name}" "${name}"
  echo "  リンク: ${name} -> ${REL_SHELL}/${name}"
done

# set-*.sh
for f in "${SCRIPT_DIR}"/set-*.sh; do
  name=$(basename "$f")
  ln -sf "${REL_SHELL}/${name}" "${name}"
  echo "  リンク: ${name} -> ${REL_SHELL}/${name}"
done

# aws-*.sh（AWSユーティリティスクリプト）
for f in "${SCRIPT_DIR}"/aws-*.sh; do
  name=$(basename "$f")
  ln -sf "${REL_SHELL}/${name}" "${name}"
  echo "  リンク: ${name} -> ${REL_SHELL}/${name}"
done

# 共通スクリプト・設定ファイル・管理スクリプト
for name in config.sh assume-role.sh del-all.sh info-all.sh reissue-accesskey.sh; do
  ln -sf "${REL_SHELL}/${name}" "${name}"
  echo "  リンク: ${name} -> ${REL_SHELL}/${name}"
done

################################################################################
# ドキュメントシンボリックリンクの作成
# infra/ からドキュメントを参照しやすくするためのリンク
################################################################################
ln -sf "../docs/構築手順/構築手順書.md" "構築手順書.md"
echo "  リンク: 構築手順書.md -> ../docs/構築手順/構築手順書.md"

################################################################################
# プロジェクトルートの lambda/ シンボリックリンクの作成
# mk-lambda.sh / mk-lambda-terminator.sh が SRC_DIR="../lambda" で参照するため
# infra/../lambda = プロジェクトルート/lambda/ が必要
################################################################################
ln -sf "src/lambda" "${PROJECT_ROOT}/lambda"
echo "  リンク: ${PROJECT_ROOT}/lambda -> src/lambda"

################################################################################
# .gitignore 作成（ログファイルを除外）
################################################################################
cat > "${INFRA_DIR}/.gitignore" << 'EOF'
*.log
EOF
echo "作成: ${INFRA_DIR}/.gitignore"

################################################################################
# 完了
################################################################################
echo ""
echo "infra/ のセットアップが完了しました。"
echo "構築手順: docs/構築手順/構築手順書.md を参照してください。"
