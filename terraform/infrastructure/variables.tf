variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used to tag/name all resources"
  type        = string
  default     = "ekart-cicd"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "AZ for the public subnet"
  type        = string
  default     = "ap-south-1a"
}

variable "key_pair_name" {
  description = "Name of the EXISTING EC2 Key Pair (created manually in the AWS console). Terraform does not create or upload this."
  type        = string
  default     = "awspem"
}


variable "instance_type" {
  description = "EC2 instance type for all five servers"
  type        = string
  default     = "m7i-flex.large"
}

variable "ubuntu_ami_owner" {
  description = "AMI owner ID for official Canonical Ubuntu images"
  type        = string
  default     = "099720109477"
}

variable "disk_sizes_gb" {
  description = "Root EBS volume size (GB) per server"
  type        = map(number)
  default = {
    jenkins     = 30
    sonarqube   = 30
    k8s_master  = 20
    k8s_worker1 = 20
    k8s_worker2 = 20
  }
}

variable "git_repo_url" {
  description = "HTTPS URL of this project's GitHub repo (e.g. https://github.com/you/ekart-cicd.git). If set, the control-plane bootstrap will automatically apply argocd/application.yaml pointing Argo CD at it. If left blank, you apply that manifest yourself after editing the placeholder URL in it."
  type        = string
  default     = ""
}

variable "nodeport_range" {
  description = "Kubernetes NodePort range to open publicly"
  type = object({
    from = number
    to   = number
  })
  default = {
    from = 30000
    to   = 33000
  }
}
