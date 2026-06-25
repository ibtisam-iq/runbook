# Phase 6: Application-Level AWS Resources

### 6A - DynamoDB Table for Cart Service

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. Create table
aws dynamodb create-table \
  --table-name cart \
  --attribute-definitions \
    AttributeName=id,AttributeType=S \
    AttributeName=customerId,AttributeType=S \
  --key-schema AttributeName=id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --global-secondary-indexes '[{
    "IndexName": "idx_global_customerId",
    "KeySchema": [{"AttributeName": "customerId","KeyType": "HASH"}],
    "Projection": {"ProjectionType": "ALL"}
  }]'

# 2. Create IAM policy
cat > cart-dynamo-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllAPIActionsOnCart",
    "Effect": "Allow",
    "Action": "dynamodb:*",
    "Resource": [
      "arn:aws:dynamodb:us-east-1:$ACCOUNT_ID:table/cart",
      "arn:aws:dynamodb:us-east-1:$ACCOUNT_ID:table/cart/index/*"
    ]
  }]
}
EOF

aws iam create-policy \
  --policy-name cart-dynamo \
  --policy-document file://cart-dynamo-policy.json

# 3. Create IRSA for cart service account
eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --namespace cart \
  --name cart \
  --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/cart-dynamo \
  --role-name dynamo-table-access-for-cart \
  --approve \
  --override-existing-serviceaccounts
```

---

### 6B - SQS Queue for Orders Service

```bash
# 1. Create queue
aws sqs create-queue --queue-name orders-events

SQS_QUEUE_ARN=$(aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/$ACCOUNT_ID/orders-events \
  --attribute-names QueueArn \
  --query "Attributes.QueueArn" \
  --output text)
echo $SQS_QUEUE_ARN
# arn:aws:sqs:us-east-1:730335615031:orders-events

# 2. Create IAM policy
cat > orders-sqs-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllAPIActionsOnOrdersQueue",
    "Effect": "Allow",
    "Action": ["sqs:CreateQueue","sqs:SendMessage","sqs:GetQueueAttributes","sqs:GetQueueUrl"],
    "Resource": "$SQS_QUEUE_ARN"
  }]
}
EOF

aws iam create-policy \
  --policy-name orders-sqs-policy \
  --policy-document file://orders-sqs-policy.json

# 3. Create IRSA for orders service account
eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --namespace orders \
  --name orders \
  --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/orders-sqs-policy \
  --role-name orders-to-sqs \
  --approve \
  --override-existing-serviceaccounts
```

---

### 6C - SNS Topic + Lambda for Order Notifications

!!! warning "IAM Constraint - Lambda created via Console"
    `iam:PassRole` and `iam:PutRolePolicy` were blocked for the lab user via CLI. The Lambda function and its event source mapping (SQS trigger) were created through the AWS Console. `AdministratorAccess` was attached to the Lambda execution role as a lab workaround.

```bash
# Create SNS topic
aws sns create-topic --name order-notifications
# TopicArn: arn:aws:sqs:$REGION:$ACCOUNT_ID:order-notifications

# Subscribe email endpoint
aws sns subscribe \
  --topic-arn arn:aws:sns:$REGION:$ACCOUNT_ID:order-notifications \
  --protocol email \
  --notification-endpoint contact@ibtisam-iq.com
# SubscriptionArn: pending confirmation
# → Confirm the subscription from the email inbox
```

```bash
# Create Lambda function
mkdir -p /tmp/lambda-fn && cat > /tmp/lambda-fn/lambda_function.py << 'EOF'
import json
import boto3

sns = boto3.client('sns')
TOPIC_ARN = "arn:aws:sns:$REGION:$ACCOUNT_ID:order-notifications"

def lambda_handler(event, context):
    for record in event['Records']:
        message = record['body']
        sns.publish(
            TopicArn=TOPIC_ARN,
            Message=f"Order confirmed: {message}"
        )
EOF

cd /tmp/lambda-fn && zip function.zip lambda_function.py

# Create trust policy
cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "lambda.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

# Create the role
aws iam create-role \
  --role-name orders-sqs-to-sns-role \
  --assume-role-policy-document file:///tmp/trust-policy.json

# Attach basic Lambda execution policy
aws iam attach-role-policy \
  --role-name orders-sqs-to-sns-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Create inline policy
cat > /tmp/inline-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["sns:Publish"],
      "Resource": "arn:aws:sns:$REGION:$ACCOUNT_ID:order-notifications"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:$REGION:$ACCOUNT_ID:orders-events"
    }
  ]
}
EOF

# Attach inline policy
aws iam put-role-policy \
  --role-name orders-sqs-to-sns-role \
  --policy-name sqs-sns-inline-policy \
  --policy-document file:///tmp/inline-policy.json  

# Wait a few seconds for IAM role to propagate
sleep 10

# create lambda function
aws lambda create-function \
  --function-name orders-sqs-to-sns \
  --runtime python3.14 \
  --role arn:aws:iam::$ACCOUNT_ID:role/orders-sqs-to-sns-role \
  --handler lambda_function.lambda_handler \
  --zip-file fileb:/tmp/lambda-fn/function.zip \
  --region $REGION  

# create event source mapping
aws lambda create-event-source-mapping \
  --function-name orders-sqs-to-sns \
  --event-source-arn arn:aws:sqs:$REGION:$ACCOUNT_ID:orders-events \
  --batch-size 10 \
  --region $REGION
```

#### Test the Pipeline

```bash
aws sqs send-message \
  --queue-url https://sqs.$REGION.$ACCOUNT_ID/orders-events \
  --message-body '{"orderId": "TEST-001", "item": "gadget", "qty": 2}' \
  --region $REGION
# MessageId: b9866851-d020-4463-88a2-4736b8e4b23a
# → Email received at contact@ibtisam-iq.com ✅
```

---
