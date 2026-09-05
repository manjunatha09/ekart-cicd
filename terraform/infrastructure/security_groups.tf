# --- Jenkins ---
resource "aws_security_group" "jenkins" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Jenkins: SSH from admin IP, 8080 public for GitHub webhook"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Jenkins UI + GitHub webhook"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-jenkins-sg" }
}

# --- SonarQube ---
resource "aws_security_group" "sonarqube" {
  name        = "${var.project_name}-sonarqube-sg"
  description = "SonarQube: SSH from admin IP, 9000 public"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "SonarQube UI"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sonarqube-sg" }
}

# --- Kubernetes (control plane + workers share one SG) ---
resource "aws_security_group" "k8s" {
  name        = "${var.project_name}-k8s-sg"
  description = "Kubernetes nodes: SSH from admin IP, NodePort public, all traffic within the SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Kubernetes NodePort range, public"
    from_port   = var.nodeport_range.from
    to_port     = var.nodeport_range.to
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-k8s-sg" }
}

# All traffic between members of the Kubernetes SG (control-plane <-> workers,
# kubelet, etcd, Calico VXLAN/BGP, etc.) without enumerating every port.
resource "aws_security_group_rule" "k8s_internal" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.k8s.id
  source_security_group_id = aws_security_group.k8s.id
  description               = "Allow all traffic between Kubernetes nodes"
}

# Jenkins -> Kubernetes API (6443), scoped to the Jenkins SG rather than
# exposed to the internet.
resource "aws_security_group_rule" "jenkins_to_k8s_api" {
  type                     = "ingress"
  from_port                = 6443
  to_port                  = 6443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s.id
  source_security_group_id = aws_security_group.jenkins.id
  description               = "Allow Jenkins to reach the Kubernetes API server"
}
