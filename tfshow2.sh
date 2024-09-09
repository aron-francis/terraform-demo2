#!/bin/bash

# Function to print a header
print_header() {
    echo "----------------------------------------"
    echo "$1"
    echo "----------------------------------------"
}

# VPC
print_header "VPC(s)"
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table

sleep 2

# Subnets
print_header "Subnets"
aws ec2 describe-subnets --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key==`Name`].Value|[0]]' --output table

sleep 2

# Internet Gateway
print_header "Internet Gateway(s)"
aws ec2 describe-internet-gateways --query 'InternetGateways[*].[InternetGatewayId,Attachments[0].VpcId]' --output table

sleep 2

# Route Table
print_header "Route Table(s)"
aws ec2 describe-route-tables --query 'RouteTables[*].[RouteTableId,VpcId,Tags[?Key==`Name`].Value|[0]]' --output table

sleep 2

# EC2 Instance
print_header "EC2 Instance(s)"
aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' --output table

sleep 2

# Lambda Functions
print_header "Lambda Function(s)"
aws lambda list-functions --query 'Functions[*].[FunctionName,Runtime,Handler]' --output table

sleep 2

# SNS Topics
print_header "SNS Topic(s)"
aws sns list-topics --query 'Topics[*].[TopicArn]' --output table

sleep 2

# CloudWatch Event Rules
print_header "CloudWatch Event Rule(s)"
aws events list-rules --query 'Rules[*].[Name,ScheduleExpression]' --output table

sleep 2


# RDS Instance
print_header "RDS Instance(s)"
aws rds describe-db-instances --query 'DBInstances[*].[DBInstanceIdentifier,Engine,DBInstanceClass,DBInstanceStatus,Endpoint.Address]' --output table || echo "No RDS instances found or an error occurred"

# Add error checking
if [ $? -ne 0 ]; then
    echo "Error: Failed to retrieve RDS instances. Check your AWS credentials and permissions."
fi
