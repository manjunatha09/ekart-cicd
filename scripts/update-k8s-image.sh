#!/bin/bash
# Manual helper that does the same edit as the Jenkinsfile's
# "Update Kubernetes Manifest" stage — useful for testing the GitOps loop
# by hand (edit deployment.yaml, commit, push, watch Argo CD sync) without
# running the full pipeline.
#
# Usage: ./update-k8s-image.sh <new-tag>
# Example: ./update-k8s-image.sh 7
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <new-tag>"
  exit 1
fi

NEW_TAG="$1"
DEPLOYMENT_FILE="kubernetes/deployment.yaml"
IMAGE="manja098/ekart"

sed -i "s|image: ${IMAGE}:.*|image: ${IMAGE}:${NEW_TAG}|g" "${DEPLOYMENT_FILE}"

echo "Updated ${DEPLOYMENT_FILE} to ${IMAGE}:${NEW_TAG}"
echo "Now commit and push:"
echo "  git add ${DEPLOYMENT_FILE}"
echo "  git commit -m \"[ci skip] deploy: ${IMAGE}:${NEW_TAG}\""
echo "  git push"
