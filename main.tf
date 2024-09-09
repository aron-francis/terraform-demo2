provider "aws" {
  region = "eu-central-1"
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "resize_instance_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "resize_instance_lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "cloudwatch:GetMetricStatistics",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}

# SNS Topic for notifications
resource "aws_sns_topic" "resize_notification" {
  name = "ec2-resize-notification"
}

# Lambda function
resource "aws_lambda_function" "resize_instance" {
  filename         = "lambda-demo2/resize_instance.zip"
  function_name    = "resize_instance"
  role             = aws_iam_role.lambda_role.arn
  handler          = "resize_instance.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.8"
  timeout          = 30  # Increase timeout to 30 seconds
  memory_size      = 256 # Increase memory to 256 MB

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.resize_notification.arn
      TARGET_INSTANCE_TYPE = "t2.micro"  // Add this line
    }
  }
}

# CloudWatch Event Rule to trigger Lambda every 4 minutes
resource "aws_cloudwatch_event_rule" "every_four_minutes" {
  name                = "every-four-minutes"
  description         = "Fires every four minutes"
  schedule_expression = "rate(4 minutes)"
}

# CloudWatch Event Target to link the rule to the Lambda function
resource "aws_cloudwatch_event_target" "check_cpu_usage" {
  rule      = aws_cloudwatch_event_rule.every_four_minutes.name
  target_id = "check_cpu_usage"
  arn       = aws_lambda_function.resize_instance.arn
}

# Lambda permission to allow CloudWatch Events to invoke the function
resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resize_instance.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.every_four_minutes.arn
}

# Output the SNS topic ARN
output "sns_topic_arn" {
  description = "ARN of the SNS topic for resize notifications"
  value       = aws_sns_topic.resize_notification.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda-demo2/resize_instance.py"
  output_path = "lambda-demo2/resize_instance.zip"
}
