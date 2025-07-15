#!/bin/bash

# Configuration file for RKE2 etcd backup script
# Copy this file and modify the values according to your environment

# S3 Configuration
export S3_BUCKET="your-etcd-backups-bucket"
export S3_PREFIX="etcd-backups"
export AWS_PROFILE="default"
export AWS_REGION="us-west-2"

# Backup Configuration
export BACKUP_DIR="/var/lib/rancher/rke2/server/db/etcd-backup"
export RETENTION_DAYS=7
export COMPRESSION_ENABLED=true

# RKE2 etcd Configuration
export ETCD_CERT_DIR="/var/lib/rancher/rke2/server/tls/etcd"
export ETCD_ENDPOINTS="https://127.0.0.1:2379"

# Optional: Custom backup naming
export BACKUP_PREFIX="etcd-backup"
export DATE_FORMAT="%Y%m%d-%H%M%S"

# Notification Configuration (optional)
export SLACK_WEBHOOK_URL=""
export EMAIL_RECIPIENTS=""

# Health Check Configuration (optional)
export HEALTHCHECK_URL=""  # For services like healthchecks.io
