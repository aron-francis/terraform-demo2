import boto3
import os

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')

    # Get all running EC2 instances
    instances = ec2.describe_instances(Filters=[{'Name': 'instance-state-name', 'Values': ['running']}])

    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']
            instance_type = instance['InstanceType']

            # Skip if already t2.micro
            if instance_type == 't2.micro':
                continue

            # Get CPU utilization for the last 4 minutes
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/EC2',
                MetricName='CPUUtilization',
                Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
                StartTime=context.get_remaining_time_in_millis() - 240000,  # 4 minutes ago
                EndTime=context.get_remaining_time_in_millis(),
                Period=240,
                Statistics=['Average']
            )

            if response['Datapoints']:
                cpu_utilization = response['Datapoints'][0]['Average']

                if cpu_utilization < 10:
                    try:
                        # Resize the instance to t2.micro
                        ec2.modify_instance_attribute(
                            InstanceId=instance_id,
                            InstanceType={'Value': 't2.micro'}
                        )

                        # Send SNS notification
                        message = f"Instance {instance_id} resized from {instance_type} to t2.micro due to low CPU utilization ({cpu_utilization:.2f}%)"
                        sns.publish(
                            TopicArn=os.environ['SNS_TOPIC_ARN'],
                            Message=message,
                            Subject="EC2 Instance Resized"
                        )
                    except Exception as e:
                        error_message = f"Failed to resize instance {instance_id}: {str(e)}"
                        sns.publish(
                            TopicArn=os.environ['SNS_TOPIC_ARN'],
                            Message=error_message,
                            Subject="EC2 Instance Resize Failed"
                        )

    return {
        'statusCode': 200,
        'body': 'Instance check completed'
    }