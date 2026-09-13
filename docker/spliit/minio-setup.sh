#!/usr/bin/env bash
# Run this yourself against your MinIO — creates a bucket-scoped user for
# Spliit instead of using the MinIO root credentials in its .env.
#
# MinIO itself runs in a container, so this runs via the official mc
# image too rather than installing mc on the host:
#
#   docker run --rm -e MINIO_ROOT_USER -e MINIO_ROOT_PASSWORD \
#     -v "$(pwd)/minio-setup.sh:/minio-setup.sh:ro" \
#     --entrypoint bash quay.io/minio/mc:latest /minio-setup.sh
#
# with MINIO_ROOT_USER / MINIO_ROOT_PASSWORD exported in your shell first
# (docker inspect core-data-minio --format '{{range .Config.Env}}{{println .}}{{end}}' | grep MINIO_ROOT
# if you need to look them up).
#
# Note: quay.io/minio/mc is a minimal RHEL UBI image with no `openssl` —
# the secret below is generated from /dev/urandom + od/tr instead, both
# of which are present.

set -euo pipefail

MINIO_ENDPOINT="http://100.111.147.14:9000"
BUCKET="spliit-vps-macauba"
SPLIIT_USER="spliit"
SPLIIT_SECRET="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"

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
