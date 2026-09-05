#!/bin/bash
# common.sh — shared setup for every Kubernetes node (master + workers).
# Prepended to the role-specific script by Terraform (see ec2.tf).
set -euxo pipefail

exec > >(tee -a /var/log/ekart-bootstrap.log) 2>&1
echo "=== common.sh starting at $(date) ==="

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# Disable swap — required by kubelet.
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Kernel modules + sysctl required by the Kubernetes networking stack.
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# --- containerd ---
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# --- kubeadm / kubelet / kubectl ---
apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' \
  | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# --- AWS CLI ---
# Used by kubernetes-master.sh / kubernetes-worker.sh to hand off the
# `kubeadm join` command via SSM Parameter Store instead of a manual SSH
# copy-paste. Auth comes from the instance's IAM role (see iam.tf) — no
# access keys anywhere on disk.
apt-get install -y unzip
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q -o /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

echo "=== common.sh finished at $(date) ==="
