#!/bin/bash

# Script to backup etcd data from RKE2 cluster and upload to S3
# Author: Vamsi Goriparthi
# Date: $(date)

set -e  # Exit on any error

# Configuration variables
BACKUP_DIR="/var/lib/rancher/rke2/server/db/etcd-backup"
BACKUP_NAME="etcd-backup-$(date +%Y%m%d-%H%M%S).db"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"
S3_BUCKET="your-s3-bucket-name"
S3_PREFIX="etcd-backups"
RETENTION_DAYS=7

# RKE2 etcd configuration
ETCD_CERT_DIR="/var/lib/rancher/rke2/server/tls/etcd"
ETCD_ENDPOINTS="https://127.0.0.1:2379"

# AWS CLI configuration (ensure AWS CLI is installed and configured)
AWS_PROFILE="default"  # Change if using specific AWS profile

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root (required for RKE2)
    if [[ $EUID -ne 0 ]]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
    
    # Check if etcdctl is available
    if ! command -v etcdctl &> /dev/null; then
        log "ERROR: etcdctl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        log "ERROR: AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check if RKE2 certificates exist
    if [[ ! -f "$ETCD_CERT_DIR/server-ca.crt" ]]; then
        log "ERROR: RKE2 etcd certificates not found at $ETCD_CERT_DIR"
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to create backup directory
create_backup_dir() {
    log "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
}

# Function to create etcd snapshot
create_etcd_snapshot() {
    log "Creating etcd snapshot: $BACKUP_PATH"
    
    ETCDCTL_API=3 etcdctl snapshot save "$BACKUP_PATH" \
        --endpoints="$ETCD_ENDPOINTS" \
        --cacert="$ETCD_CERT_DIR/server-ca.crt" \
        --cert="$ETCD_CERT_DIR/server-client.crt" \
        --key="$ETCD_CERT_DIR/server-client.key"
    
    if [[ $? -eq 0 ]]; then
        log "Snapshot created successfully: $BACKUP_PATH"
        log "Snapshot size: $(du -h "$BACKUP_PATH" | cut -f1)"
    else
        log "ERROR: Failed to create etcd snapshot"
        exit 1
    fi
}

# Function to verify snapshot
verify_snapshot() {
    log "Verifying snapshot integrity..."
    
    ETCDCTL_API=3 etcdctl snapshot status "$BACKUP_PATH" \
        --write-out=table
    
    if [[ $? -eq 0 ]]; then
        log "Snapshot verification completed successfully"
    else
        log "ERROR: Snapshot verification failed"
        exit 1
    fi
}

# Function to compress backup
compress_backup() {
    log "Compressing backup..."
    gzip "$BACKUP_PATH"
    BACKUP_PATH="${BACKUP_PATH}.gz"
    BACKUP_NAME="${BACKUP_NAME}.gz"
    log "Backup compressed: $BACKUP_PATH"
    log "Compressed size: $(du -h "$BACKUP_PATH" | cut -f1)"
}

# Function to upload to S3
upload_to_s3() {
    log "Uploading backup to S3..."
    
    S3_KEY="$S3_PREFIX/$(hostname)/$BACKUP_NAME"
    
    aws s3 cp "$BACKUP_PATH" "s3://$S3_BUCKET/$S3_KEY" \
        --profile "$AWS_PROFILE" \
        --storage-class STANDARD_IA \
        --metadata "hostname=$(hostname),timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ),cluster=rke2"
    
    if [[ $? -eq 0 ]]; then
        log "Backup uploaded successfully to s3://$S3_BUCKET/$S3_KEY"
    else
        log "ERROR: Failed to upload backup to S3"
        exit 1
    fi
}

# Function to cleanup old local backups
cleanup_local_backups() {
    log "Cleaning up local backups older than $RETENTION_DAYS days..."
    
    find "$BACKUP_DIR" -name "etcd-backup-*.db*" -type f -mtime +$RETENTION_DAYS -delete
    
    log "Local cleanup completed"
}

# Function to cleanup old S3 backups
cleanup_s3_backups() {
    log "Cleaning up S3 backups older than $RETENTION_DAYS days..."
    
    CUTOFF_DATE=$(date -u -d "$RETENTION_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ)
    
    aws s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --prefix "$S3_PREFIX/$(hostname)/" \
        --query "Contents[?LastModified<='$CUTOFF_DATE'].Key" \
        --output text \
        --profile "$AWS_PROFILE" | \
    while read -r key; do
        if [[ -n "$key" ]]; then
            aws s3 rm "s3://$S3_BUCKET/$key" --profile "$AWS_PROFILE"
            log "Deleted old S3 backup: $key"
        fi
    done
    
    log "S3 cleanup completed"
}

# Main execution
main() {
    log "Starting etcd backup process for RKE2 cluster"
    
    check_prerequisites
    create_backup_dir
    create_etcd_snapshot
    verify_snapshot
    compress_backup
    upload_to_s3
    cleanup_local_backups
    cleanup_s3_backups
    
    log "Backup process completed successfully"
    log "Backup location: s3://$S3_BUCKET/$S3_PREFIX/$(hostname)/$BACKUP_NAME"
}

# Run main function
main "$@"
