provider "aws" {
  region = "us-east-1" # Change to your desired AWS region
}

resource "aws_s3_bucket" "data_bucket" {
  bucket = "your-data-bucket-name"
  acl    = "private"
}

resource "aws_lambda_function" "data_processing" {
  filename      = "lambda_function.zip" # Lambda code
  function_name = "data-processing-function"
  handler       = "lambda_handler"
  runtime       = "python3.8"

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.data_bucket.id
    }
  }

  source_code_hash = filebase64sha256("lambda_function.zip")

  role = aws_iam_role.lambda_execution_role.arn
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "s3_policy" {
  name        = "s3_policy"
  description = "Policy for Lambda to access S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
      ],
      Effect   = "Allow",
      Resource = [
        aws_s3_bucket.data_bucket.arn,
        "${aws_s3_bucket.data_bucket.arn}/*",
      ],
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_policy_attachment" {
  policy_arn = aws_iam_policy.s3_policy.arn
  role       = aws_iam_role.lambda_execution_role.name
}

resource "aws_sns_topic" "notification_topic" {
  name = "data-processing-notification-topic"
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_processing.function_name
  principal     = "sns.amazonaws.com"

  source_arn = aws_sns_topic.notification_topic.arn
}

resource "aws_eventbridge_rule" "s3_event_rule" {
  name        = "s3-event-rule"
  description = "Rule to trigger Lambda on S3 event"
  event_pattern = <<EOF
{
  "source": ["aws.s3"],
  "detail": {
    "eventName": ["PutObject"]
  },
  "resources": ["${aws_s3_bucket.data_bucket.arn}"]
}
EOF
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_processing.function_name
  principal     = "events.amazonaws.com"

  source_arn = aws_eventbridge_rule.s3_event_rule.arn
}

