#!/bin/bash
set -ex

# Log all output
exec > >(tee /var/log/user-data.log) 2>&1
echo "Starting user data script at $(date)"

# Parameters passed directly from Terraform (these will be substituted)
DB_HOST="${DB_HOST}"
DB_PORT="${DB_PORT}"
DB_USER="${DB_USER}"
DB_PASSWORD="${DB_PASSWORD}"
DB_NAME="${DB_NAME}"
PORT="${PORT}"
AWS_REGION="${AWS_REGION}"
S3_BUCKET_NAME="${S3_BUCKET_NAME}"

echo "Parameters received:"
echo "DB_HOST: $DB_HOST"
echo "DB_PORT: $DB_PORT"
echo "DB_USER: $DB_USER"
echo "DB_NAME: $DB_NAME"
echo "PORT: $PORT"
echo "AWS_REGION: $AWS_REGION"
echo "S3_BUCKET_NAME: $S3_BUCKET_NAME"

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

# Create .env file directly with the parameters passed from Terraform
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
EOF

# Set permissions for .env file
chmod 600 /opt/myapp/.env
chown csye6225:csye6225 /opt/myapp/.env

echo "Environment file created successfully at /opt/myapp/.env"
cat /opt/myapp/.env

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
After=network.target
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

# Reload systemd, enable and start webapp service
echo "Configuring and starting webapp service..."
systemctl daemon-reload
systemctl enable webapp
systemctl start webapp || echo "Failed to start webapp service"
systemctl status webapp || echo "Failed to get webapp service status"

echo "User data script completed at $(date)"