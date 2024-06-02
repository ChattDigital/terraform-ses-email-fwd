import os

import boto3
import email


s3 = boto3.client('s3')
ses = boto3.client('ses')

def lambda_handler(event, context):
    bucket_name = os.environ['BUCKET_NAME']
    destination_email = os.environ['DESTINATION_EMAIL']
    key = event['Records'][0]['ses']['mail']['messageId']

    # Get the email from the S3 bucket
    response = s3.get_object(Bucket=bucket_name, Key=f'emails/{key}')
    raw_email = response['Body'].read().decode('utf-8')

    # Parse the email
    msg = email.message_from_string(raw_email)

    # Extract the relevant parts of the email
    source_email = msg['From']
    destination_email = msg['To']
    subject = msg['Subject']
    body = msg.get_payload(decode=True)

    # Forward the email
    response = ses.send_raw_email(
        Source=source_email,
        Destinations=[destination_email],
        RawMessage={
            'Data': raw_email
        }
    )

    return {
        'statusCode': 200,
        'body': f"Email from {source_email} forwarded to {destination_email}"
    }
