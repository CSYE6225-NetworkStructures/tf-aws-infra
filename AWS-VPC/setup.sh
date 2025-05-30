#!/bin/bash
set -ex

# Log all output
exec > >(tee /var/log/user-data.log) 2>&1
echo "Starting user data script at $(date)"

# Parameters passed directly from Terraform (these will be substituted)
DB_SECRET_ARN="${DB_SECRET_ARN}"
PORT="${PORT}"
AWS_REGION="${AWS_REGION}"
S3_BUCKET_NAME="${S3_BUCKET_NAME}"

echo "Parameters received:"
echo "DB_SECRET_ARN: $DB_SECRET_ARN"
echo "PORT: $PORT"
echo "AWS_REGION: $AWS_REGION"
echo "S3_BUCKET_NAME: $S3_BUCKET_NAME"

# Install AWS CLI and dependencies
echo "Installing AWS CLI and dependencies..."
apt-get update
apt-get install -y curl unzip wget jq python3-pip

# Install AWS CLI v2
echo "Installing AWS CLI v2..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -f awscliv2.zip
rm -rf aws

# Get instance ID for CloudWatch 
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id || echo "unknown-instance")
echo "Running on EC2 instance: $INSTANCE_ID"

# Install CloudWatch Agent
echo "Installing AWS CloudWatch Agent..."
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb

# Create CloudWatch agent configuration
echo "Creating CloudWatch Agent configuration..."
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/

# Create the CloudWatch configuration file
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root",
    "region": "${AWS_REGION}"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "webapp-logs",
            "log_stream_name": "{instance_id}-userdata",
            "retention_in_days": 7
          },
          {
            "file_path": "/opt/myapp/logs/application.log",
            "log_group_name": "webapp-logs",
            "log_stream_name": "{instance_id}-application",
            "retention_in_days": 7
          },
          {
            "file_path": "/opt/myapp/logs/error.log",
            "log_group_name": "webapp-logs",
            "log_stream_name": "{instance_id}-error",
            "retention_in_days": 7
          }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "statsd": {
        "service_address": ":8125",
        "metrics_collection_interval": 60,
        "metrics_aggregation_interval": 60
      }
    }
  }
}
EOF

# Set permissions on CloudWatch config
chmod 644 /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Create application user if not exists
if ! id csye6225 &>/dev/null; then
    echo "Creating csye6225 user..."
    useradd -m -d /home/csye6225 -s /bin/bash csye6225
    echo "csye6225 ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/csye6225
    chmod 440 /etc/sudoers.d/csye6225
fi

# Make sure the app directory exists
mkdir -p /opt/myapp
chown csye6225:csye6225 /opt/myapp
chmod 750 /opt/myapp

# Create logs directory and required log files
echo "Creating logs directory and log files..."
mkdir -p /opt/myapp/logs
touch /opt/myapp/logs/application.log
touch /opt/myapp/logs/error.log
chown -R csye6225:csye6225 /opt/myapp/logs
chmod -R 750 /opt/myapp/logs

# Retrieve database credentials from Secrets Manager with error handling
echo "Retrieving database credentials from Secrets Manager..."
set +e  # Don't exit on error for this part
SECRET_RESULT=$(aws secretsmanager get-secret-value --secret-id $DB_SECRET_ARN --region $AWS_REGION 2>&1)
SECRET_STATUS=$?
set -e  # Resume exit on error

if [ $SECRET_STATUS -ne 0 ]; then
    echo "ERROR: Failed to retrieve secret from Secrets Manager: $SECRET_RESULT"
    echo "Checking IAM role and permissions..."
    aws sts get-caller-identity
    echo "Checking Secret ARN format and existence..."
    aws secretsmanager list-secrets --region $AWS_REGION | grep $DB_SECRET_ARN || echo "Secret not found"
    # Fall back to default credentials for testing purposes
    echo "Using fallback database credentials for testing"
    DB_HOST="localhost"
    DB_PORT="3306"
    DB_USER="root"
    DB_PASSWORD="Welcome1234"
    DB_NAME="health_check"
else
    SECRET_JSON=$(echo $SECRET_RESULT | jq -r '.SecretString')
    DB_HOST=$(echo $SECRET_JSON | jq -r '.host')
    DB_PORT=$(echo $SECRET_JSON | jq -r '.port')
    DB_USER=$(echo $SECRET_JSON | jq -r '.username')
    DB_PASSWORD=$(echo $SECRET_JSON | jq -r '.password')
    DB_NAME=$(echo $SECRET_JSON | jq -r '.dbname')
    echo "Database connection details retrieved successfully"
    echo "DB_HOST: $DB_HOST"
    echo "DB_PORT: $DB_PORT"
    echo "DB_USER: $DB_USER"
    echo "DB_NAME: $DB_NAME"
fi

# Create .env file with retrieved parameters
echo "Creating .env file with provided parameters..."
cat > /opt/myapp/.env << EOF
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_NAME=$DB_NAME
PORT=$PORT
AWS_REGION=$AWS_REGION
S3_BUCKET_NAME=$S3_BUCKET_NAME
LOG_DIRECTORY=/opt/myapp/logs
ENABLE_FILE_LOGGING=true
CLOUDWATCH_GROUP_NAME=webapp-logs
ENABLE_METRICS=true
STATSD_HOST=localhost
STATSD_PORT=8125
INSTANCE_ID=$INSTANCE_ID
EOF

# Set permissions for .env file
chmod 600 /opt/myapp/.env
chown csye6225:csye6225 /opt/myapp/.env

echo "Environment file created successfully at /opt/myapp/.env"

# Check if webapp binary exists
if [ -f "/opt/myapp/webapp" ]; then
    echo "Webapp binary found, setting permissions..."
    chmod +x /opt/myapp/webapp
    chown csye6225:csye6225 /opt/myapp/webapp
else
    echo "ERROR: webapp binary not found at /opt/myapp/webapp"
    ls -la /opt/myapp/
fi

# Create systemd service file with existence check for .env
cat > /etc/systemd/system/webapp.service << 'EOF'
[Unit]
Description=My Node.js Application
After=network.target amazon-cloudwatch-agent.service
Wants=amazon-cloudwatch-agent.service
ConditionPathExists=/opt/myapp/.env

[Service]
Type=simple
User=csye6225
Group=csye6225
WorkingDirectory=/opt/myapp
ExecStart=/opt/myapp/webapp
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=webapp
Environment=NODE_ENV=production
EnvironmentFile=/opt/myapp/.env

[Install]
WantedBy=multi-user.target
EOF

# Start CloudWatch agent
echo "Starting CloudWatch agent..."
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Verify CloudWatch agent status
echo "Verifying CloudWatch agent status..."
systemctl status amazon-cloudwatch-agent || echo "CloudWatch agent status check failed, but continuing..."

# Reload systemd, enable and start webapp service
echo "Configuring and starting webapp service..."
systemctl daemon-reload
systemctl enable webapp
systemctl start webapp || echo "Failed to start webapp service"
systemctl status webapp || echo "Failed to get webapp service status"

# Send test metrics to verify StatsD
echo "Sending test metrics to verify StatsD configuration..."
apt-get install -y netcat
echo "test.metric:1|c" | nc -u -w0 127.0.0.1 8125
echo "test.timer:100|ms" | nc -u -w0 127.0.0.1 8125

echo "User data script completed at $(date)"