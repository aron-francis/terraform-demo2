import boto3
import os
import logging
from botocore.exceptions import ClientError
from datetime import datetime, timedelta

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')

    logger.info("Lambda function started")

    target_type = os.environ.get('TARGET_INSTANCE_TYPE', 't2.micro')
    logger.info(f"Target instance type: {target_type}")

    try:
        # Check both running and stopped instances
        instances = ec2.describe_instances(Filters=[{'Name': 'instance-state-name', 'Values': ['running', 'stopped']}])
        running_instances = []
        stopped_instances = []

        for reservation in instances['Reservations']:
            for instance in reservation['Instances']:
                if instance['State']['Name'] == 'running':
                    running_instances.append(instance)
                elif instance['State']['Name'] == 'stopped':
                    stopped_instances.append(instance)

        logger.info(f"Found {len(running_instances)} running instances and {len(stopped_instances)} stopped instances")

        # Process running instances
        for instance in running_instances:
            process_instance(ec2, cloudwatch, sns, instance, target_type)

        # Process stopped instances
        for instance in stopped_instances:
            if instance['InstanceType'] != target_type:
                logger.info(f"Stopped instance {instance['InstanceId']} is of type {instance['InstanceType']}. Modifying and starting...")
                try:
                    ec2.modify_instance_attribute(
                        InstanceId=instance['InstanceId'],
                        InstanceType={'Value': target_type}
                    )
                    ec2.start_instances(InstanceIds=[instance['InstanceId']])
                    message = f"Instance {instance['InstanceId']} modified from {instance['InstanceType']} to {target_type} and started"
                    logger.info(message)
                    sns.publish(
                        TopicArn=os.environ['SNS_TOPIC_ARN'],
                        Message=message,
                        Subject="EC2 Instance Modified and Started"
                    )
                except ClientError as e:
                    error_message = f"Error modifying and starting instance {instance['InstanceId']}: {str(e)}"
                    logger.error(error_message)
                    sns.publish(
                        TopicArn=os.environ['SNS_TOPIC_ARN'],
                        Message=error_message,
                        Subject="EC2 Instance Modification Error"
                    )

    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=f"Unexpected error in Lambda function: {str(e)}",
            Subject="EC2 Resize Lambda Error"
        )

    logger.info("Lambda function completed")
    return {
        'statusCode': 200,
        'body': 'Instance check completed'
    }

def process_instance(ec2, cloudwatch, sns, instance, target_type):
    instance_id = instance['InstanceId']
    instance_type = instance['InstanceType']
    logger.info(f"Checking running instance {instance_id} of type {instance_type}")

    if instance_type == target_type:
        logger.info(f"Instance {instance_id} already at target type. Skipping.")
        return

    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=1)

    logger.info(f"Querying CloudWatch for CPU utilization from {start_time} to {end_time}")
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='CPUUtilization',
            Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average']
        )
        logger.info(f"CloudWatch response for {instance_id}: {response}")

        if response['Datapoints']:
            datapoints = sorted(response['Datapoints'], key=lambda x: x['Timestamp'], reverse=True)
            cpu_utilization = datapoints[0]['Average']
            logger.info(f"Instance {instance_id} CPU utilization: {cpu_utilization}%")

            if cpu_utilization < 10:
                resize_instance(ec2, sns, instance_id, instance_type, target_type, cpu_utilization)
        else:
            logger.warning(f"No CPU utilization data for instance {instance_id} in the last hour")
    except ClientError as e:
        logger.error(f"Error getting CloudWatch metrics for instance {instance_id}: {str(e)}")

def resize_instance(ec2, sns, instance_id, current_type, target_type, cpu_utilization):
    logger.info(f"Attempting to resize instance {instance_id}")
    try:
        ec2.stop_instances(InstanceIds=[instance_id])
        waiter = ec2.get_waiter('instance_stopped')
        waiter.wait(InstanceIds=[instance_id])
        logger.info(f"Instance {instance_id} stopped")

        ec2.modify_instance_attribute(
            InstanceId=instance_id,
            InstanceType={'Value': target_type}
        )
        logger.info(f"Instance {instance_id} type modified to {target_type}")

        ec2.start_instances(InstanceIds=[instance_id])
        logger.info(f"Instance {instance_id} started")

        message = f"Instance {instance_id} resized from {current_type} to {target_type} due to low CPU utilization ({cpu_utilization:.2f}%)"
        logger.info(message)
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=message,
            Subject="EC2 Instance Resized"
        )
    except ClientError as e:
        error_message = f"Error resizing instance {instance_id}: {str(e)}"
        logger.error(error_message)
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=error_message,
            Subject="EC2 Instance Resize Error"
        )