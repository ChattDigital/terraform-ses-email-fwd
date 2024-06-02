# terraform-ses-email-fwd
Terraform for AWS SES setup and email forwarding to an external email address.

## Assumptions
This terraform configuration assumes that you have an AWS account with a Route53 hosted zone and that you have set up the appropriate access to Route53, SES, S3, and Lambda.

## Instructions

### Authentication
Export your AWS credentials:
```
export AWS_ACCESS_KEY_ID=<your_access_key>
export AWS_SECRET_ACCESS_KEY=<your_secret_access_key>
```

### Set terraform variables
Copy the example terraform variables and update them with the correct values:
```
cp terraform.tfvars.sample terraform.tfvars
```

### Apply Terraform Config
Initialize and apply the terraform configuration:
```
terraform init
terraform apply
```
