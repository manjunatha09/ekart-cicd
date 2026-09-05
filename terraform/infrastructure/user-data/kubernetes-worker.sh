#!/bin/bash
# kubernetes-worker.sh — runs after common.sh on each worker instance.
# Templated by Terraform (see ec2.tf): $${master_private_ip}, $${aws_region},
# and $${ssm_param_name} are substituted at apply time.
set -euxo pipefail

exec > >(tee -a /var/log/ekart-bootstrap.log) 2>&1
echo "=== kubernetes-worker.sh starting at $(date) ==="

MASTER_IP="${master_private_ip}"
AWS_REGION="${aws_region}"
SSM_PARAM_NAME="${ssm_param_name}"

# 1) Wait for the control plane's API server to actually be reachable
#    before attempting anything, instead of a blind `sleep 60`.
echo "Waiting for control plane API at $${MASTER_IP}:6443 ..."
for i in $(seq 1 60); do
  if (echo > /dev/tcp/"$${MASTER_IP}"/6443) >/dev/null 2>&1; then
    echo "Control plane API is reachable."
    break
  fi
  echo "  ... not ready yet (attempt $${i}/60), sleeping 15s"
  sleep 15
done

# 2) Automated join: poll SSM Parameter Store for the join command the
#    control plane publishes once it finishes `kubeadm init`. This
#    replaces the old manual "SSH in and paste the join command" step —
#    auth is via the instance's IAM role (see iam.tf), no credentials on
#    disk in either direction.
echo "Waiting for join command in SSM parameter $${SSM_PARAM_NAME} ..."
JOIN_CMD=""
for i in $(seq 1 60); do
  if JOIN_CMD=$(aws ssm get-parameter \
        --region "$${AWS_REGION}" \
        --name "$${SSM_PARAM_NAME}" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text 2>/dev/null); then
    if [[ -n "$${JOIN_CMD}" && "$${JOIN_CMD}" != "None" ]]; then
      echo "Join command retrieved from SSM."
      break
    fi
  fi
  echo "  ... not published yet (attempt $${i}/60), sleeping 15s"
  JOIN_CMD=""
  sleep 15
done

if [[ -z "$${JOIN_CMD}" ]]; then
  echo "ERROR: never received a join command from SSM after 15 minutes."
  echo "Check the control plane's /var/log/ekart-bootstrap.log, then run manually:"
  echo "  aws ssm get-parameter --region $${AWS_REGION} --name $${SSM_PARAM_NAME} --with-decryption --query Parameter.Value --output text | sudo bash"
  exit 1
fi

echo "Joining cluster..."
eval "sudo $${JOIN_CMD}"

touch /home/ubuntu/WORKER_JOINED

echo "=== kubernetes-worker.sh finished at $(date) ==="
