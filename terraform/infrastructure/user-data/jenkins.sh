#!/bin/bash
# jenkins.sh — bootstraps the Jenkins EC2 instance.
# Installs: Java 21, Jenkins, Maven, Docker, Git, Trivy,
# OWASP Dependency-Check CLI, and kubectl.

set -euxo pipefail

exec > >(tee -a /var/log/ekart-bootstrap.log) 2>&1

echo "=== jenkins.sh starting at $(date) ==="

export DEBIAN_FRONTEND=noninteractive

# --------------------------------------------------
# System packages
# --------------------------------------------------

apt-get update -y
apt-get upgrade -y

apt-get install -y \
  fontconfig \
  openjdk-21-jre \
  git \
  maven \
  unzip \
  curl \
  gnupg \
  apt-transport-https \
  ca-certificates

# --------------------------------------------------
# Jenkins
# --------------------------------------------------

mkdir -p /etc/apt/keyrings

curl -fsSL \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
  -o /etc/apt/keyrings/jenkins-keyring.asc

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | tee /etc/apt/sources.list.d/jenkins.list > /dev/null

apt-get update -y
apt-get install -y jenkins

systemctl enable jenkins
systemctl start jenkins

# --------------------------------------------------
# Docker
# --------------------------------------------------

curl -fsSL https://get.docker.com | sh

usermod -aG docker jenkins
usermod -aG docker ubuntu

systemctl enable docker
systemctl restart docker

# --------------------------------------------------
# Trivy
# --------------------------------------------------

curl -fsSL \
  https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
  | sh -s -- -b /usr/local/bin

# --------------------------------------------------
# OWASP Dependency-Check CLI
# --------------------------------------------------

DC_VERSION="10.0.4"

curl -L -o /tmp/dependency-check.zip \
  "https://github.com/jeremylong/DependencyCheck/releases/download/v${DC_VERSION}/dependency-check-${DC_VERSION}-release.zip"

unzip -q /tmp/dependency-check.zip -d /opt

ln -sf \
  /opt/dependency-check/bin/dependency-check.sh \
  /usr/local/bin/dependency-check

# --------------------------------------------------
# kubectl
# Jenkins uses kubectl only for cluster verification.
# Deployment is handled by Argo CD.
# --------------------------------------------------

curl -LO \
  "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

rm -f kubectl

# --------------------------------------------------
# Restart Jenkins after Docker installation
# --------------------------------------------------

systemctl restart jenkins

# --------------------------------------------------
# Verification
# --------------------------------------------------

echo "=== Installed versions ==="

java -version
mvn -version
git --version
docker --version
kubectl version --client
trivy --version
dependency-check --version || true

echo "=== Jenkins status ==="
systemctl --no-pager --full status jenkins || true

echo "=== jenkins.sh finished at $(date) ==="

echo "Initial admin password:"
cat /var/lib/jenkins/secrets/initialAdminPassword || true