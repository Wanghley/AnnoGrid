#!/usr/bin/env bash
# Run this yourself against your MinIO — creates a bucket-scoped user for
# Spliit instead of using the MinIO root credentials in its .env. Needs
# the `mc` (MinIO Client) CLI: https://min.io/docs/minio/linux/reference/minio-mc.html
#
# Usage:
#   MINIO_ROOT_USER=... MINIO_ROOT_PASSWORD=... ./minio-setup.sh
#
# Substitute your actual MinIO root credentials (docker inspect
# core-data-minio, or whatever you set MINIO_ROOT_USER/PASSWORD to) —
# not hardcoded here on purpose.

set -euo pipefail

MINIO_ENDPOINT="http://100.111.147.14:9000"
BUCKET="spliit-vps-macauba"
SPLIIT_USER="spliit"
SPLIIT_SECRET="$(openssl rand -hex 24)"

: "${MINIO_ROOT_USER:?Set MINIO_ROOT_USER}"
: "${MINIO_ROOT_PASSWORD:?Set MINIO_ROOT_PASSWORD}"

mc alias set spliit-admin "$MINIO_ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

# Bucket for expense attachments.
mc mb --ignore-existing "spliit-admin/$BUCKET"

# Dedicated user, not the root account.
mc admin user add spliit-admin "$SPLIIT_USER" "$SPLIIT_SECRET"

# Policy scoped to only this bucket — read/write objects, list the
# bucket, nothing else (no access to other buckets, no admin actions).
cat > /tmp/spliit-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::${BUCKET}/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::${BUCKET}"]
    }
  ]
}
EOF

mc admin policy create spliit-admin spliit-bucket-policy /tmp/spliit-policy.json
mc admin policy attach spliit-admin spliit-bucket-policy --user "$SPLIIT_USER"
rm /tmp/spliit-policy.json

echo "Done. Add these to docker/spliit/.env:"
echo "  S3_UPLOAD_KEY=${SPLIIT_USER}"
echo "  S3_UPLOAD_SECRET=${SPLIIT_SECRET}"
