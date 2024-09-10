#!/bin/bash

# Function to print a header
print_header() {
    echo "----------------------------------------"
    echo "$1"
    echo "----------------------------------------"
}

# Function to print resource count
print_count() {
    echo "----------------------------------------"
    echo "Total resources: $1"
    echo "----------------------------------------"
}

# Function to count resources
count_resources() {
    echo "$1" | sed '1,2d' | grep -v '^|--' | grep -v '^\+--' | grep -v '^$' | wc -l
}

# Variable to keep track of total resources
total_resources=0
: <<'END_COMMENT'
# VPC
print_header "VPC(s)"
vpc_output=$(aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table)
echo "$vpc_output"
vpc_count=$(count_resources "$vpc_output")
print_count $vpc_count
total_resources=$((total_resources + vpc_count))

sleep 2

# Subnets
print_header "Subnets"
subnet_output=$(aws ec2 describe-subnets --query 'Subnets[*].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key==`Name`].Value|[0]]' --output table)
echo "$subnet_output"
subnet_count=$(count_resources "$subnet_output")
print_count $subnet_count
total_resources=$((total_resources + subnet_count))

sleep 2

# Internet Gateway
print_header "Internet Gateway(s)"
igw_output=$(aws ec2 describe-internet-gateways --query 'InternetGateways[*].[InternetGatewayId,Attachments[0].VpcId]' --output table)
echo "$igw_output"
igw_count=$(count_resources "$igw_output")
print_count $igw_count
total_resources=$((total_resources + igw_count))

sleep 2

# Route Table
print_header "Route Table(s)"
rt_output=$(aws ec2 describe-route-tables --query 'RouteTables[*].[RouteTableId,VpcId,Tags[?Key==`Name`].Value|[0]]' --output table)
echo "$rt_output"
rt_count=$(count_resources "$rt_output")
print_count $rt_count
total_resources=$((total_resources + rt_count))

sleep 2
END_COMMENT

# EC2 Instance - Excluding Terminated
print_header "EC2 Instance(s) - Excluding Terminated"
ec2_output=$(aws ec2 describe-instances \
    --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' \
    --output table)
echo "$ec2_output"
ec2_count=$(count_resources "$ec2_output")
print_count $ec2_count
total_resources=$((total_resources + ec2_count))

sleep 2

# Lambda Functions
print_header "Lambda Function(s)"
lambda_output=$(aws lambda list-functions --query 'Functions[*].[FunctionName,Runtime,Handler]' --output table)
echo "$lambda_output"
lambda_count=$(count_resources "$lambda_output")
print_count $lambda_count
total_resources=$((total_resources + lambda_count))

sleep 2

# SNS Topics
print_header "SNS Topic(s)"
sns_output=$(aws sns list-topics --query 'Topics[*].[TopicArn]' --output table)
echo "$sns_output"
sns_count=$(count_resources "$sns_output")
print_count $sns_count
total_resources=$((total_resources + sns_count))

sleep 2
