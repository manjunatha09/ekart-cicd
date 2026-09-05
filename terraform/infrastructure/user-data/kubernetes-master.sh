#!/bin/bash
# kubernetes-master.sh — runs after common.sh on the control-plane instance.
# Templated by Terraform (see ec2.tf): $${aws_region}, $${ssm_param_name},
# and $${git_repo_url} are substituted at apply time. Existing bash
# variables use $$ instead of $ throughout so Terraform's templatefile()
# doesn't try to interpolate them.
set -euxo pipefail

exec > >(tee -a /var/log/ekart-bootstrap.log) 2>&1
echo "=== kubernetes-master.sh starting at $(date) ==="

AWS_REGION="${aws_region}"
SSM_PARAM_NAME="${ssm_param_name}"
GIT_REPO_URL="${git_repo_url}"

PRIVATE_IP=$(hostname -I | awk '{print $1}')

kubeadm init \
  --apiserver-advertise-address="$${PRIVATE_IP}" \
  --pod-network-cidr=192.168.0.0/16

mkdir -p /home/ubuntu/.kube
cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config

export KUBECONFIG=/etc/kubernetes/admin.conf

# --- Calico CNI ---
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

# --- Argo CD ---
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose the Argo CD UI via NodePort so it's reachable the same way the
# app is (falls inside the 30000-33000 range opened in the SG).
kubectl -n argocd patch svc argocd-server -p '{"spec": {"type": "NodePort"}}'

# --- Automated worker join: publish the join command to SSM Parameter
#     Store instead of a file the operator has to SSH-copy by hand. ---
JOIN_CMD=$(kubeadm token create --print-join-command)

aws ssm put-parameter \
  --region "$${AWS_REGION}" \
  --name "$${SSM_PARAM_NAME}" \
  --type "SecureString" \
  --value "$${JOIN_CMD}" \
  --overwrite

echo "Join command published to SSM parameter $${SSM_PARAM_NAME}."
echo "$${JOIN_CMD}" > /home/ubuntu/join-command.sh
chmod +x /home/ubuntu/join-command.sh

# Readiness marker (kept for convenience/manual debugging).
touch /home/ubuntu/CONTROL_PLANE_READY

# --- Optional: auto-apply the Argo CD Application if a repo URL was given ---
if [[ -n "$${GIT_REPO_URL}" ]]; then
  echo "GIT_REPO_URL provided — installing the Argo CD Application manifest automatically."
  # Written inline (rather than fetched from the repo, which may not be
  # reachable/public at boot time) with the repo URL substituted in.
  cat <<APPEOF > /home/ubuntu/argocd-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ekart-cicd
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $${GIT_REPO_URL}
    targetRevision: main
    path: kubernetes
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
APPEOF
  # Argo CD's CRDs/pods can take a minute or two to become ready after
  # `kubectl apply` above, so wait for the Application CRD before using it.
  for i in $(seq 1 30); do
    if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
      break
    fi
    sleep 10
  done
  kubectl apply -f /home/ubuntu/argocd-application.yaml || echo "Argo CD Application apply failed — apply /home/ubuntu/argocd-application.yaml manually once Argo CD is fully up."
else
  echo "No GIT_REPO_URL provided — skipping auto-apply. Edit and apply argocd/application.yaml from the repo manually."
fi

echo "=== kubernetes-master.sh finished at $(date) ==="
echo "Argo CD initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d || true
echo
