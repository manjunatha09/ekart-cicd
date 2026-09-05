#!/bin/bash
# sonarqube.sh — bootstraps the SonarQube EC2 instance by running the
# official sonarqube:community Docker image.
set -euxo pipefail

exec > >(tee -a /var/log/ekart-bootstrap.log) 2>&1
echo "=== sonarqube.sh starting at $(date) ==="

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# SonarQube's embedded Elasticsearch needs this bumped, or it will
# crash-loop on boot.
cat <<EOF | tee -a /etc/sysctl.conf
vm.max_map_count=262144
fs.file-max=65536
EOF
sysctl --system

curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker

docker volume create sonarqube_data
docker volume create sonarqube_logs
docker volume create sonarqube_extensions

docker run -d \
  --name sonarqube \
  --restart unless-stopped \
  -p 9000:9000 \
  -v sonarqube_data:/opt/sonarqube/data \
  -v sonarqube_logs:/opt/sonarqube/logs \
  -v sonarqube_extensions:/opt/sonarqube/extensions \
  sonarqube:community

echo "=== sonarqube.sh finished at $(date) ==="
echo "SonarQube will take 1-2 minutes to become ready at :9000 (default login admin/admin)."
