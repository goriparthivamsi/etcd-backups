#!/bin/bash

# Script to restore etcd data from S3 backup for RKE2 cluster
# Author: Generated for RKE2 etcd restore automation
# Date: $(date)

set -e  # Exit on any error

# Configuration variables
BACKUP_DIR="/var/lib/rancher/rke2/server/db/etcd-backup"
S3_BUCKET="your-s3-bucket-name"
S3_PREFIX="etcd-backups"
AWS_PROFILE="default"
RKE2_DATA_DIR="/var/lib/rancher/rke2/server/db/etcd"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
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
    
    log "Prerequisites check completed successfully"
}

# Function to list available backups
list_backups() {
    log "Available backups in S3:"
    
    aws s3 ls "s3://$S3_BUCKET/$S3_PREFIX/$(hostname)/" \
        --profile "$AWS_PROFILE" \
        --human-readable \
        --summarize
}

# Function to download backup from S3
download_backup() {
    local backup_file="$1"
    
    if [[ -z "$backup_file" ]]; then
        log "ERROR: No backup file specified"
        exit 1
    fi
    
    log "Downloading backup: $backup_file"
    
    mkdir -p "$BACKUP_DIR"
    
    S3_KEY="$S3_PREFIX/$(hostname)/$backup_file"
    LOCAL_PATH="$BACKUP_DIR/$backup_file"
    
    aws s3 cp "s3://$S3_BUCKET/$S3_KEY" "$LOCAL_PATH" \
        --profile "$AWS_PROFILE"
    
    if [[ $? -eq 0 ]]; then
        log "Backup downloaded successfully to: $LOCAL_PATH"
    else
        log "ERROR: Failed to download backup from S3"
        exit 1
    fi
    
    # Decompress if needed
    if [[ "$backup_file" == *.gz ]]; then
        log "Decompressing backup..."
        gunzip "$LOCAL_PATH"
        LOCAL_PATH="${LOCAL_PATH%.gz}"
        log "Backup decompressed to: $LOCAL_PATH"
    fi
    
    echo "$LOCAL_PATH"
}

# Function to stop RKE2 service
stop_rke2() {
    log "Stopping RKE2 service..."
    
    systemctl stop rke2-server.service
    
    # Wait for service to stop
    sleep 10
    
    if systemctl is-active --quiet rke2-server.service; then
        log "ERROR: Failed to stop RKE2 service"
        exit 1
    fi
    
    log "RKE2 service stopped successfully"
}

# Function to backup current etcd data
backup_current_etcd() {
    log "Creating backup of current etcd data..."
    
    CURRENT_BACKUP="$BACKUP_DIR/current-etcd-backup-$(date +%Y%m%d-%H%M%S)"
    
    if [[ -d "$RKE2_DATA_DIR" ]]; then
        cp -r "$RKE2_DATA_DIR" "$CURRENT_BACKUP"
        log "Current etcd data backed up to: $CURRENT_BACKUP"
    else
        log "WARNING: Current etcd data directory not found: $RKE2_DATA_DIR"
    fi
}

# Function to restore etcd data
restore_etcd() {
    local backup_file="$1"
    
    log "Restoring etcd data from: $backup_file"
    
    # Remove existing etcd data
    if [[ -d "$RKE2_DATA_DIR" ]]; then
        rm -rf "$RKE2_DATA_DIR"
        log "Existing etcd data removed"
    fi
    
    # Create new data directory
    mkdir -p "$(dirname "$RKE2_DATA_DIR")"
    
    # Restore from snapshot
    ETCDCTL_API=3 etcdctl snapshot restore "$backup_file" \
        --data-dir="$RKE2_DATA_DIR" \
        --name="$(hostname)" \
        --initial-cluster="$(hostname)=https://$(hostname):2380" \
        --initial-cluster-token="etcd-cluster-1" \
        --initial-advertise-peer-urls="https://$(hostname):2380"
    
    if [[ $? -eq 0 ]]; then
        log "Etcd data restored successfully"
    else
        log "ERROR: Failed to restore etcd data"
        exit 1
    fi
    
    # Set correct ownership
    chown -R rke2:rke2 "$RKE2_DATA_DIR"
    
    log "Ownership set for restored data"
}

# Function to start RKE2 service
start_rke2() {
    log "Starting RKE2 service..."
    
    systemctl start rke2-server.service
    
    # Wait for service to start
    sleep 30
    
    if systemctl is-active --quiet rke2-server.service; then
        log "RKE2 service started successfully"
    else
        log "ERROR: Failed to start RKE2 service"
        exit 1
    fi
}

# Function to verify cluster health
verify_cluster_health() {
    log "Verifying cluster health..."
    
    # Wait for API server to be ready
    timeout=300
    while [[ $timeout -gt 0 ]]; do
        if kubectl get nodes &>/dev/null; then
            log "API server is responding"
            break
        fi
        sleep 10
        timeout=$((timeout - 10))
    done
    
    if [[ $timeout -eq 0 ]]; then
        log "WARNING: API server not responding after 5 minutes"
        return 1
    fi
    
    # Check node status
    kubectl get nodes
    
    # Check system pods
    kubectl get pods -n kube-system
    
    log "Cluster verification completed"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] <backup-filename>"
    echo ""
    echo "Options:"
    echo "  -l, --list          List available backups"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 etcd-backup-20240715-123456.db.gz"
    echo ""
    echo "Note: This script will:"
    echo "  1. Stop the RKE2 service"
    echo "  2. Backup current etcd data"
    echo "  3. Download and restore the specified backup"
    echo "  4. Start the RKE2 service"
    echo "  5. Verify cluster health"
}

# Main function
main() {
    case "${1:-}" in
        -l|--list)
            check_prerequisites
            list_backups
            exit 0
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        "")
            log "ERROR: No backup file specified"
            show_usage
            exit 1
            ;;
        *)
            BACKUP_FILE="$1"
            ;;
    esac
    
    log "Starting etcd restore process for RKE2 cluster"
    log "Backup file: $BACKUP_FILE"
    
    # Warning prompt
    read -p "WARNING: This will stop RKE2 and replace etcd data. Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Restore cancelled by user"
        exit 0
    fi
    
    check_prerequisites
    
    # Download backup
    LOCAL_BACKUP=$(download_backup "$BACKUP_FILE")
    
    # Perform restore
    stop_rke2
    backup_current_etcd
    restore_etcd "$LOCAL_BACKUP"
    start_rke2
    verify_cluster_health
    
    log "Restore process completed successfully"
    log "Please verify your cluster is functioning correctly"
}

# Run main function
main "$@"
