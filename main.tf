terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.52.0"
    }
  }

  backend "s3" {
    bucket  = "chattdigital-ses-email-fwd-tfstate"
    key     = "terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_tag
      Terraform = "true"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_route53_zone" "selected" {
  name = var.zone_name
}

###
# S3 bucket for storing emails
###
resource "aws_s3_bucket" "email_bucket" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_ownership_controls" "email_bucket_ownership_controls" {
  bucket = aws_s3_bucket.email_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "email_bucket_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.email_bucket_ownership_controls]

  bucket = aws_s3_bucket.email_bucket.id
  acl    = "private"
}

resource "aws_s3_bucket_policy" "email_bucket_policy" {
  bucket = aws_s3_bucket.email_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowSESPuts"
        Effect = "Allow"
        Principal = {
          Service = "ses.amazonaws.com"
        },
        Action   = "s3:PutObject",
        Resource = "${aws_s3_bucket.email_bucket.arn}/*",
        Condition = {
          StringEquals = {
            "aws:Referer" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}


###
# SES domain verification
###
resource "aws_ses_domain_identity" "domain" {
  domain = var.domain
}

resource "aws_route53_record" "ses_verification" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "_amazonses.${var.domain}."
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.domain.verification_token]
}


###
# SES MX record to allow receiving emails
###
resource "aws_route53_record" "mx_record" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.domain
  type    = "MX"
  ttl    = 300
  records = ["10 inbound-smtp.${var.aws_region}.amazonaws.com"]
}


###
# Lambda function to forward emails
###
resource "aws_iam_role" "lambda_role" {
  name = "lambda_email_forwarding_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# allow lambda role to read from S3 bucket
resource "aws_iam_policy_attachment" "lambda_s3_access" {
  name       = "lambda_s3_access"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# allow lambda role to send emails
resource "aws_iam_policy_attachment" "lambda_ses_access" {
  name       = "lambda_ses_access"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonSESFullAccess"
}

# allow lambda role to log to CloudWatch
resource "aws_iam_policy_attachment" "lambda_logging" {
  name       = "lambda_logging"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# create the lambda function to forward emails
resource "aws_lambda_function" "email_forwarding_function" {
  filename         = "lambda.zip"
  function_name    = "EmailForwardingFunction"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda.lambda_handler"
  source_code_hash = filebase64sha256("lambda.zip")
  runtime          = "python3.12"
  environment {
    variables = {
      BUCKET_NAME       = aws_s3_bucket.email_bucket.bucket
      SOURCE_EMAIL      = var.source_email
      DESTINATION_EMAIL = var.destination_email
    }
  }
}

# allow lambda to be invoked by SES
resource "aws_lambda_permission" "ses_invokes" {
  statement_id  = "AllowSESToInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.email_forwarding_function.function_name
  principal     = "ses.amazonaws.com"
}


###
# SES receipt rule to forward emails to s3 bucket
###
resource "aws_ses_receipt_rule_set" "default" {
  rule_set_name = "default-rule-set"
}

# create the rule
resource "aws_ses_receipt_rule" "email_forwarding_rule" {
  rule_set_name = aws_ses_receipt_rule_set.default.rule_set_name
  name          = "EmailForwardingRule"
  recipients    = [var.source_email]

  add_header_action {
    header_name  = "X-Original-To"
    header_value = var.source_email
    position     = 1
  }

  # save email to S3 bucket
  s3_action {
    bucket_name       = aws_s3_bucket.email_bucket.bucket
    object_key_prefix = "emails/"
    position          = 2
  }

  # trigger lambda function to forward email
  lambda_action {
    function_arn    = aws_lambda_function.email_forwarding_function.arn
    invocation_type = "Event"
    position        = 3
  }

  enabled      = true
  scan_enabled = true
}

# activate the ruleset
resource "aws_ses_active_receipt_rule_set" "default" {
  rule_set_name = aws_ses_receipt_rule_set.default.rule_set_name
}
