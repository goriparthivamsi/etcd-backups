# RKE2 etcd Backup and Restore Scripts

This repository contains scripts for backing up and restoring etcd data in RKE2 clusters with S3 integration.

## Files Overview

- `etcd-backup.sh` - Main backup script that creates etcd snapshots and uploads to S3
- `etcd-restore.sh` - Restoration script to restore etcd from S3 backups
- `backup-config.sh` - Configuration file template
- `etcd-backup.service` - Systemd service file for automated backups
- `etcd-backup.timer` - Systemd timer for scheduling backups

## Prerequisites

### 1. System Requirements
- RKE2 cluster with etcd running
- Root access on RKE2 server nodes
- `etcdctl` tool installed
- AWS CLI installed and configured

### 2. Install Dependencies

```bash
# Install AWS CLI (if not already installed)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install etcdctl (if not already installed)
ETCD_VER=v3.5.0
curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o etcd-${ETCD_VER}-linux-amd64.tar.gz
tar xzf etcd-${ETCD_VER}-linux-amd64.tar.gz
sudo mv etcd-${ETCD_VER}-linux-amd64/etcdctl /usr/local/bin/
```

### 3. AWS Configuration

Configure AWS credentials:
```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, region, and output format
```

Or use IAM roles for EC2 instances (recommended for production).

### 4. S3 Bucket Setup

Create an S3 bucket for backups:
```bash
aws s3 mb s3://your-etcd-backups-bucket
```

## Setup Instructions

### 1. Configuration

1. Copy the configuration template:
   ```bash
   cp backup-config.sh /etc/rke2/backup-config.sh
   ```

2. Edit the configuration file:
   ```bash
   sudo nano /etc/rke2/backup-config.sh
   ```

3. Update the following variables:
   - `S3_BUCKET`: Your S3 bucket name
   - `AWS_PROFILE`: Your AWS profile (default: "default")
   - `AWS_REGION`: Your AWS region
   - `RETENTION_DAYS`: Number of days to keep backups

### 2. Script Installation

1. Copy scripts to appropriate location:
   ```bash
   sudo cp etcd-backup.sh /usr/local/bin/
   sudo cp etcd-restore.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/etcd-backup.sh
   sudo chmod +x /usr/local/bin/etcd-restore.sh
   ```

2. Update script configuration:
   ```bash
   sudo nano /usr/local/bin/etcd-backup.sh
   ```
   Update the S3_BUCKET and other variables at the top of the script.

### 3. Manual Backup

Test the backup script manually:
```bash
sudo /usr/local/bin/etcd-backup.sh
```

### 4. Automated Backup Setup

1. Install systemd service and timer:
   ```bash
   sudo cp etcd-backup.service /etc/systemd/system/
   sudo cp etcd-backup.timer /etc/systemd/system/
   ```

2. Update the service file with correct script path:
   ```bash
   sudo nano /etc/systemd/system/etcd-backup.service
   ```
   Update the `ExecStart` line to point to your script location.

3. Enable and start the timer:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable etcd-backup.timer
   sudo systemctl start etcd-backup.timer
   ```

4. Check timer status:
   ```bash
   sudo systemctl status etcd-backup.timer
   sudo systemctl list-timers etcd-backup.timer
   ```

## Usage

### Manual Backup
```bash
sudo /usr/local/bin/etcd-backup.sh
```

### List Available Backups
```bash
sudo /usr/local/bin/etcd-restore.sh --list
```

### Restore from Backup
```bash
sudo /usr/local/bin/etcd-restore.sh etcd-backup-20240715-123456.db.gz
```

## Script Features

### Backup Script (`etcd-backup.sh`)
- Creates etcd snapshots with proper RKE2 certificates
- Verifies snapshot integrity
- Compresses backups to save space
- Uploads to S3 with metadata
- Cleans up old local and S3 backups
- Comprehensive logging
- Error handling and validation

### Restore Script (`etcd-restore.sh`)
- Lists available backups in S3
- Downloads and decompresses backups
- Safely stops RKE2 service
- Backs up current etcd data before restore
- Restores etcd from snapshot
- Starts RKE2 service
- Verifies cluster health

## Monitoring and Logging

### Check Backup Status
```bash
# View recent logs
sudo journalctl -u etcd-backup.service -f

# Check last backup run
sudo systemctl status etcd-backup.service
```

### View S3 Backups
```bash
aws s3 ls s3://your-etcd-backups-bucket/etcd-backups/ --recursive --human-readable
```

## Security Considerations

1. **Encryption**: Enable S3 server-side encryption
2. **Access Control**: Use IAM roles with minimal required permissions
3. **Network Security**: Ensure secure communication between nodes
4. **Backup Validation**: Regularly test restore procedures

## Troubleshooting

### Common Issues

1. **Permission Errors**
   - Ensure script runs as root
   - Check file permissions on certificates

2. **Certificate Issues**
   - Verify RKE2 certificates exist in expected location
   - Check certificate expiration

3. **S3 Upload Failures**
   - Verify AWS credentials and permissions
   - Check network connectivity
   - Ensure S3 bucket exists and is accessible

4. **etcdctl Command Failures**
   - Verify etcdctl is installed and in PATH
   - Check etcd service status
   - Verify endpoint connectivity

### Validation Commands

```bash
# Check etcd health
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key

# Check RKE2 service status
sudo systemctl status rke2-server.service

# Check cluster nodes
kubectl get nodes
```

## Best Practices

1. **Regular Testing**: Test restore procedures regularly
2. **Multiple Backups**: Keep backups from multiple time points
3. **Cross-Region**: Consider cross-region S3 replication
4. **Monitoring**: Set up alerts for backup failures
5. **Documentation**: Keep recovery procedures documented
6. **Access Control**: Limit access to backup files

## Support

For RKE2-specific issues, consult the [Rancher RKE2 documentation](https://docs.rke2.io/).

For etcd backup/restore procedures, refer to the [etcd documentation](https://etcd.io/docs/).

## License

This project is provided as-is for educational and operational use.
