################################################################################
# ec2、vmのshutdown後に呼び出される
#
# author      : tsystem
# Last updated: 2025-11-19 00:29:24 (added by ts-add-version.sh)
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)
ec2_client = boto3.client('ec2')

def handler(event, context):
    """
    EventBridgeからEC2の停止イベントを受け取り、対象のインスタンスを削除する
    """
    # 例外発生時に対象IDをログへ出すための初期値
    instance_id = "" # for error logging
    try:
        # イベントからインスタンスIDを取得
        instance_id = event['detail']['instance-id']
        logger.info(f"Received stop event for instance: {instance_id}")

        # インスタンスの情報を取得してタグを確認
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        
        # インスタンスが見つからない場合のエラーハンドリング
        if not response['Reservations'] or not response['Reservations'][0]['Instances']:
            logger.warning(f"Instance {instance_id} not found. It might have been terminated already.")
            return {
                'statusCode': 200,
                'body': f"Instance {instance_id} not found, skipping."
            }
            
        instance = response['Reservations'][0]['Instances'][0]
        tags = instance.get('Tags', [])
        
        # 削除対象のタグがあるかチェック
        is_target = False
        for tag in tags:
            if tag.get('Key') == 'autogen-by' and tag.get('Value') == 'ts-010-system':
                is_target = True
                break
        
        # 自動生成されたインスタンスのみ終了させる。意図しない本番機を誤停止させないようにするガード。
        if is_target:
            logger.info(f"Instance {instance_id} has the 'autogen-by: ts-010-system' tag. Proceeding with termination.")
            ec2_client.terminate_instances(InstanceIds=[instance_id])
            logger.info(f"Successfully initiated termination for instance: {instance_id}")
            return {
                'statusCode': 200,
                'body': f"Termination initiated for {instance_id}"
            }
        else:
            logger.info(f"Instance {instance_id} does not have the required tag. Skipping termination.")
            return {
                'statusCode': 200,
                'body': f"Instance {instance_id} skipped (not a target)."
            }

    except Exception as e:
        logger.error(f"Error processing instance {instance_id}: {e}")
        # tracebackをログに出力
        import traceback
        logger.error(traceback.format_exc())
        raise e
