#!/bin/bash
# jenkins.sh — bootstraps the Jenkins EC2 instance.
# Installs: Java, Jenkins, Maven, Docker, Git, Trivy, OWASP Dependency-Check
# CLI, and kubectl (so Jenkins can run `kubectl get nodes/pods` against the
# cluster over the Jenkins-SG -> K8s-SG :6443 rule).
set -euxo pipefail

exec > >(tee -a /var/log/ekart-bootstrap.log) 2>&1
echo "=== jenkins.sh starting at $(date) ==="

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

apt-get install -y fontconfig openjdk-17-jre git maven unzip curl gnupg apt-transport-https

# --- Jenkins ---
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
  | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
apt-get update -y
apt-get install -y jenkins
systemctl enable jenkins
systemctl start jenkins

# --- Docker (Jenkins needs it to build/push the app image) ---
curl -fsSL https://get.docker.com | sh
usermod -aG docker jenkins
usermod -aG docker ubuntu
systemctl enable docker
systemctl restart docker

# --- Trivy ---
curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sh -s -- -b /usr/local/bin

# --- OWASP Dependency-Check CLI ---
DC_VERSION="10.0.4"
curl -L -o /tmp/dependency-check.zip \
  "https://github.com/jeremylong/DependencyCheck/releases/download/v${DC_VERSION}/dependency-check-${DC_VERSION}-release.zip"
unzip -q /tmp/dependency-check.zip -d /opt
ln -sf /opt/dependency-check/bin/dependency-check.sh /usr/local/bin/dependency-check

# --- kubectl (so Jenkins can verify the cluster; deploys still go through Argo CD) ---
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

systemctl restart jenkins

echo "=== jenkins.sh finished at $(date) ==="
echo "Initial admin password:"
cat /var/lib/jenkins/secrets/initialAdminPassword || true
