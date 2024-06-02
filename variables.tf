variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "S3 bucket name"
  type        = string
}

variable "domain" {
  description = "Domain name"
  type        = string
}

variable "zone_name" {
  description = "Route 53 zone name"
  type        = string
}

variable "source_email" {
  description = "Email address to forward emails from"
  type        = string
}

variable "destination_email" {
  description = "Email address to forward emails to"
  type        = string
}

variable "project_tag" {
  description = "Project tag"
  type        = string
  default     = "ses-email-fwd"
}
