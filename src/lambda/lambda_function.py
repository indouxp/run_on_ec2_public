################################################################################
# S3バケットへのファイル(.conf)アップロードをトリガーに実行される
#
# author      : tsystem
# Last updated: 2025-11-19 00:28:21
#

import json
import boto3
import os
import logging
import traceback
import re

################################################################################
# ログ出力設定。CloudWatch Logs に出力されます。
logger = logging.getLogger()
logger.setLevel(logging.INFO)

################################################################################
# 環境変数から設定値を取得
# なし

################################################################################
# 各 AWS サービスにアクセスするためのクライアント初期化
ec2_client = boto3.client('ec2')
s3_client = boto3.client('s3')
iam_client = boto3.client('iam')
sns_client = boto3.client('sns')
ses_client = boto3.client('ses')

################################################################################
def validate_config(config):
    """設定ファイルの内容をバリデーションする"""
    logger.info("Starting configuration validation.")

    # 必須キーが存在するか
    required_keys = ['exec', 'log', 'result', 'mail', 'sms', 'ec2_role_name', 'subnet_name', 'sg_name', 'ec2_instance_name_tag', 'output_bucket', 'ses_from_email', 'prj_prefix']
    for key in required_keys:
        if key not in config:
            raise ValueError(f"Configuration error: Missing required key '{key}'.")

    # mailのフォーマットチェック
    if not re.fullmatch(r".+@.+\..+", config['mail']):
        raise ValueError(f"Configuration error: Invalid email format for 'mail': {config['mail']}.")

    # smsのフォーマットチェック (日本の+81形式を想定)
    if not isinstance(config['sms'], str) or not config['sms'].startswith('+81') or not config['sms'][1:].isdigit():
        raise ValueError(f"Configuration error: Invalid SMS format for 'sms'. Must be a string starting with '+81'. Found: {config['sms']}")

    # ses_from_emailのフォーマットチェック
    if not re.fullmatch(r".+@.+\..+", config['ses_from_email']):
        raise ValueError(f"Configuration error: Invalid email format for 'ses_from_email': {config['ses_from_email']}.")

    # ebs_sizeの範囲チェック(10G〜1000G)
    if 'ebs_size' in config:
        try:
            ebs_size = int(config['ebs_size'])
        except (ValueError, TypeError):
            raise ValueError(f"Configuration error: 'ebs_size' must be an integer. Found: {config['ebs_size']}.")

        if not 10 <= ebs_size <= 1000:
            raise ValueError(f"Configuration error: 'ebs_size' must be between 10 and 1000. Found: {ebs_size}.")

    # ebs_type のチェック
    if 'ebs_type' in config:
        valid_ebs_types = ['gp3', 'gp2', 'io1', 'io2']
        if config['ebs_type'] not in valid_ebs_types:
            raise ValueError(f"Configuration error: 'ebs_type' must be one of {valid_ebs_types}. Found: {config['ebs_type']}.")

    # timeout のチェック
    if 'timeout' in config:
        try:
            timeout = int(config['timeout'])
        except (ValueError, TypeError):
            raise ValueError(f"Configuration error: 'timeout' must be an integer. Found: {config['timeout']}.")

        if not 60 <= timeout <= 21600:
            raise ValueError(f"Configuration error: 'timeout' must be between 60 and 21600. Found: {timeout}.")
    
    logger.info("Configuration validation successful.")

################################################################################
def check_if_instance_is_running(instance_name_tag):
    """指定された名前タグを持つインスタンスが起動中か確認する"""
    logger.info(f"Checking for running instances with tag: {instance_name_tag}")
    
    response = ec2_client.describe_instances(
        Filters=[
            {
                'Name': 'tag:Name',
                'Values': [instance_name_tag]
            },
            {
                'Name': 'instance-state-name',
                'Values': ['pending', 'running']
            }
        ]
    )
    
    if response['Reservations']:
        logger.warning(f"Found running or pending instance with name tag: {instance_name_tag}")
        return True
    
    logger.info(f"No running or pending instances found with name tag: {instance_name_tag}")
    return False

################################################################################
def get_resource_ids(config):
    """必要なAWSリソースのIDをタグ名から取得する"""
    resources = {}
    
    subnet_name = config.get('subnet_name', 'ts-010-subnet-010')
    sg_name = config.get('sg_name', 'ts-010-sg-010')
    ec2_role_name = config.get('ec2_role_name', 'ts-010-role-ec2-010')

    subnets = ec2_client.describe_subnets(Filters=[{'Name': 'tag:Name', 'Values': [subnet_name]}])
    if not subnets['Subnets']:
        raise ValueError(f"Subnet with name '{subnet_name}' not found.")
    resources['subnet_id'] = subnets['Subnets'][0]['SubnetId']
    
    sgs = ec2_client.describe_security_groups(Filters=[{'Name': 'group-name', 'Values': [sg_name]}])
    if not sgs['SecurityGroups']:
        raise ValueError(f"Security Group with name '{sg_name}' not found.")
    resources['sg_id'] = sgs['SecurityGroups'][0]['GroupId']
    
    try:
        profile = iam_client.get_instance_profile(InstanceProfileName=ec2_role_name)
        resources['instance_profile_arn'] = profile['InstanceProfile']['Arn']
    except iam_client.exceptions.NoSuchEntityException:
        raise ValueError(f"IAM Instance Profile '{ec2_role_name}' not found.")
        
    return resources

################################################################################
def send_error_notification(error, context, config):
    """エラー内容をSNSとSESで通知する"""

    if context is None:
        # ローカル実行などでcontextが渡らない場合でも通知本文を整形できるようにする
        context = type('dummy', (object,), {})()
        context.function_name = "Unknown"
        context.aws_request_id = "Unknown"
        context.log_stream_name = "Unknown"

    subject = f"FAILED: EC2 Job Trigger Lambda ({context.function_name})"
    
    message = (
        f"Lambda Function Name: {context.function_name}\n"
        f"AWS Request ID: {context.aws_request_id}\n"
        f"Log Stream: {context.log_stream_name}\n"
        f"Configuration: {json.dumps(config, indent=2)}\n\n"
        f"Error: {str(error)}\n\n"
        f"Traceback:\n{traceback.format_exc()}"
    )
    
    # --- SNS 通知 ---
    # configにsms番号があれば利用し、なければ何もしない
    sms_to = config.get('sms')
    if sms_to:
        try:
            # SNSトピックではなく、電話番号に直接送信
            sns_client.publish(
                PhoneNumber=sms_to,
                Message=f"[Error] Lambda: {context.function_name}. See email for details."
            )
            logger.info(f"Successfully sent error notification to SMS: {sms_to}")
        except Exception as e:
            logger.error(f"Failed to send SNS notification to {sms_to}: {e}")
    else:
        logger.warning("SMS number not found in config. Skipping SNS notification.")


    # --- SES (Email) 通知 ---
    mail_to = config.get('mail')
    ses_from_email = config.get('ses_from_email')
    if not ses_from_email:
        logger.error("SES_FROM_EMAIL not found in config. Cannot send email.")
        return
        
    if mail_to:
        try:
            ses_client.send_email(
                Source=ses_from_email,
                Destination={'ToAddresses': [mail_to]},
                Message={
                    'Subject': {'Data': subject, 'Charset': 'UTF-8'},
                    'Body': {'Text': {'Data': message, 'Charset': 'UTF-8'}}
                }
            )
            logger.info(f"Successfully sent error notification to Email: {mail_to}")
        except Exception as e:
            logger.error(f"Failed to send SES notification to {mail_to}: {e}")
    else:
        logger.warning("Email address ('mail') not found in config. Skipping SES notification.")

################################################################################
def main_handler(event, context):
    """
    S3イベントをトリガーにEC2インスタンスを起動する。エントリーポイント
    """
    # 例外時に通知へ詳細を渡せるよう、初期値を先に用意しておく
    config = {} # エラー通知で使えるように上位スコープで定義
    try:
        # S3イベントの基本情報を抽出
        s3_event = event['Records'][0]['s3']
        bucket_name = s3_event['bucket']['name']
        conf_key = s3_event['object']['key']

        logger.info(f"Triggered by S3 event='{s3_event}: bucket='{bucket_name}', key='{conf_key}'")

        # 設定ファイル以外のアップロードは処理対象外
        if not conf_key.endswith('.conf'):
            logger.info(f"Object '{conf_key}' is not a .conf file. Skipping.")
            return {'statusCode': 200, 'body': 'Not a .conf file, skipped.'}

        # S3から設定ファイルを取得しJSONとして解釈
        response = s3_client.get_object(Bucket=bucket_name, Key=conf_key)
        config_str = response['Body'].read().decode('utf-8')
        config = json.loads(config_str)
        logger.info(f"Loaded config: {config}")
        
        # 設定ファイルのバリデーションを実行
        validate_config(config)

        # 同一インスタンスが実行中でないか確認
        instance_name_tag = config.get('ec2_instance_name_tag', 'ts-010-ec2-010')
        if check_if_instance_is_running(instance_name_tag):
            raise ValueError(f"An instance with the name tag '{instance_name_tag}' is already running or pending.")

        # 起動に必要な各種リソースIDをタグ名から解決
        resource_ids = get_resource_ids(config)
        logger.info(f"Found resource IDs: {resource_ids}")

        # configから値を取得
        ec2_instance_name_tag = config.get('ec2_instance_name_tag', 'ts-010-ec2-010')
        output_bucket = config.get('output_bucket', '${BKT_OUT}')
        default_ami_id = config.get('default_ami_id', 'ami-09ed31f8f34719e20')
        instance_type = config.get('instance_type', 'c6i.4xlarge')
        ses_from_email = config.get('ses_from_email')

        # 入力が欠けても最低限の動作を担保するためのデフォルト値群
        prj_prefix = config.get('prj_prefix', 'ts-010')

        # UserDataテンプレートを読み込み
        try:
            # Lambdaの実行環境では、テンプレートはカレントディレクトリにあると想定
            with open('./user_data_template.sh', 'r') as f:
                user_data_script_template = f.read()
        except FileNotFoundError:
            # ローカルでのテスト実行など、配置が異なる場合を考慮
            try:
                script_dir = os.path.dirname(os.path.abspath(__file__))
                template_path = os.path.join(script_dir, '../shell/user_data_template.sh')
                with open(template_path, 'r') as f:
                    user_data_script_template = f.read()
            except FileNotFoundError:
                logger.error("UserData template file not found in standard locations.")
                raise

        # テンプレートへ各種値を埋め込み、EC2に渡すユーザーデータを組み立てる
        logger.info(f"config['exec']={config['exec']}")
        logger.info(f"bucket_name={bucket_name}")
        logger.info(f"config.get('log')={config.get('log', 'job.log')}")
        logger.info(f"result={config.get('result', 'job.result')}")
        logger.info(f"config['mail']={config['mail']}")
        logger.info(f"config['sms']={config['sms']}")
        logger.info(f"ses_from_email={ses_from_email}")
        logger.info(f"ec2_client.meta.region_name={ec2_client.meta.region_name}")
        user_data_script = user_data_script_template.format(
            T_PRJ_PREFIX=prj_prefix,
            T_EXEC_COMMAND=config['exec'],
            T_BUCKET_NAME=bucket_name,
            T_OUTPUT_BUCKET=output_bucket,
            T_LOG_FILE=config.get('log', 'job.log'),
            T_RESULT_FILE=config.get('result', 'job.result'),
            T_MAIL_TO=config['mail'],
            T_SMS_TO=config['sms'],
            T_SES_FROM=ses_from_email,
            T_AWS_REGION=ec2_client.meta.region_name
        )

        # EC2起動パラメータを構築
        instance_params = {
            'ImageId': config.get('ami_id', default_ami_id),
            'InstanceType': config.get('instance_type', 'c6i.4xlarge'),
            'IamInstanceProfile': {
                'Arn': resource_ids['instance_profile_arn']
            },
            'NetworkInterfaces': [
                {
                    'DeviceIndex': 0,
                    'SubnetId': resource_ids['subnet_id'],
                    'Groups': [resource_ids['sg_id']],
                    'AssociatePublicIpAddress': True
                }
            ],
            'UserData': user_data_script,
            'TagSpecifications': [
                {
                    'ResourceType': 'instance',
                    'Tags': [
                        {
                            'Key': 'Name',
                            'Value': ec2_instance_name_tag
                        },
                        {
                            'Key': 'autogen-by',
                            'Value': 'ts-010-system'
                        }
                    ]
                },
            ],
            'MinCount': 1,
            'MaxCount': 1
        }

        # KeyNameが指定されていれば追加
        if 'key_name' in config:
            instance_params['KeyName'] = config['key_name']

        # EBSサイズまたはEBSタイプが指定されていればBlockDeviceMappingsを上書き
        if 'ebs_size' in config or 'ebs_type' in config:
            ebs_params = {
                'DeleteOnTermination': True  # 終了時にEBSも削除
            }
            if 'ebs_size' in config:
                ebs_params['VolumeSize'] = int(config['ebs_size'])
            if 'ebs_type' in config:
                ebs_params['VolumeType'] = config['ebs_type']
            instance_params['BlockDeviceMappings'] = [
                {
                    'DeviceName': '/dev/xvda',
                    'Ebs': ebs_params
                }
            ]

        # UserDataはログに出力すると長すぎるので除外
        log_params = {k: v for k, v in instance_params.items() if k != 'UserData'}
        logger.info(f"Launching EC2 instance with params: {log_params}")
        
        # インスタンス起動をリクエスト
        response = ec2_client.run_instances(**instance_params)
        instance_id = response['Instances'][0]['InstanceId']
        logger.info(f"Successfully initiated launch of EC2 instance: {instance_id}")

        # インスタンスがrunning状態になるのを待つ
        logger.info(f"Waiting for instance {instance_id} to enter 'running' state...")
        waiter = ec2_client.get_waiter('instance_running')
        try:
            # Lambdaのタイムアウトを考慮し、最大で約4分30秒待つ (15秒 * 18回)
            waiter.wait(
                InstanceIds=[instance_id],
                WaiterConfig={
                    'Delay': 15,
                    'MaxAttempts': 18
                }
            )
            logger.info(f"Instance {instance_id} is now running.")
        except Exception as e: # WaiterErrorはbotocore.exceptions.WaiterErrorだが、一般的なExceptionで捕捉
            logger.error(f"Instance {instance_id} did not enter 'running' state in time. Terminating it.")
            ec2_client.terminate_instances(InstanceIds=[instance_id])
            logger.info(f"Terminated instance {instance_id}.")
            # エラーを再発生させ、メインの例外処理に渡す
            raise e

        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully launched EC2 instance {instance_id}')
        }

    except Exception as e:
        logger.error(f"Error: {e}")
        logger.error(traceback.format_exc())
        send_error_notification(e, context, config)
        raise e
