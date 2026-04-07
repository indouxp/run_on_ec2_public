#!/bin/bash

# =================================================================
# AWSリソース 共通設定ファイル
# =================================================================

# -----------------------------------------------------------------
# 基本設定
# -----------------------------------------------------------------
# AWSリージョン
export AWS_REGION="ap-northeast-1"

# プロジェクトプレフィックス
export PRJ_PREFIX="ts-010"

# -----------------------------------------------------------------
# ネットワーク関連
# -----------------------------------------------------------------
# VPC名
export VPC_NAME="${PRJ_PREFIX}-vpc-010"
# Subnet名
export SUBNET_NAME="${PRJ_PREFIX}-subnet-010"
# Internet Gateway名
export IGW_NAME="${PRJ_PREFIX}-igw-010"
# セキュリティグループ名
export SG_NAME="${PRJ_PREFIX}-sg-010"

# -----------------------------------------------------------------
# ストレージ関連
# -----------------------------------------------------------------
# S3入力バケット名
export S3_BKT_IN_NAME="${PRJ_PREFIX}-bkt-in"
# S3出力バケット名
export S3_BKT_OUT_NAME="${PRJ_PREFIX}-bkt-out"

# -----------------------------------------------------------------
# IAM関連
# -----------------------------------------------------------------
# Lambda実行IAMロール名
export IAM_ROLE_LAMBDA_NAME="${PRJ_PREFIX}-role-lambda-010"
# Lambdaカスタムポリシー名
export IAM_POLICY_LAMBDA_NAME="${PRJ_PREFIX}-lambda-custom-policy-010"
# EC2実行IAMロール名
export IAM_ROLE_EC2_NAME="${PRJ_PREFIX}-role-ec2-010"
# EC2カスタムポリシー名
export IAM_POLICY_EC2_NAME="${PRJ_PREFIX}-ec2-custom-policy"

# -----------------------------------------------------------------
# コンピューティング & トリガー関連
# -----------------------------------------------------------------
# Lambda関数名
export LAMBDA_FUNC_NAME="${PRJ_PREFIX}-lmd-010"
# S3トリガーID
export S3_TRIGGER_ID="${PRJ_PREFIX}-lambda-trigger"


# -----------------------------------------------------------------
# 監視 & 通知関連
# -----------------------------------------------------------------
# CloudWatch Lambdaロググループ名
export CW_LOG_GROUP_LAMBDA_NAME="${PRJ_PREFIX}-log-lambda-010"
# CloudWatch EC2ロググループ名
export CW_LOG_GROUP_EC2_NAME="${PRJ_PREFIX}-log-ec2-010"
# CloudWatch システムロググループ名
export CW_LOG_GROUP_SYSTEM_NAME="${PRJ_PREFIX}-log-system-010"
# SNS通知トピック名
export SNS_TOPIC_NAME="${PRJ_PREFIX}-sns-010"

# -----------------------------------------------------------------
# User & Management Roles
# -----------------------------------------------------------------
# IAMユーザー名
export IAM_USER_NAME="${PRJ_PREFIX}-user"
# インフラ構築用IAMロール名
export IAM_ROLE_BUILD_NAME="${PRJ_PREFIX}-role-build"
# 実行用IAMロール名
export IAM_ROLE_EXEC_NAME="${PRJ_PREFIX}-role-exec"

