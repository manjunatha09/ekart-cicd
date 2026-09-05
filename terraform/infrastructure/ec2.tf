locals {
  common_tags = {
    Project = var.project_name
  }

  # Referenced by iam.tf (to scope the SSM permission) and by the master
  # and worker user-data scripts (to write/read the join command).
  ssm_join_command_param = "/${var.project_name}/k8s-join-command"
}

# --- Jenkins ---
resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.ubuntu_24_04.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_base.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.disk_sizes_gb["jenkins"]
    volume_type = "gp3"
  }

  user_data = file("${path.module}/user-data/jenkins.sh")

  tags = merge(local.common_tags, { Name = "${var.project_name}-jenkins" })
}

# --- SonarQube ---
resource "aws_instance" "sonarqube" {
  ami                         = data.aws_ami.ubuntu_24_04.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.sonarqube.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.disk_sizes_gb["sonarqube"]
    volume_type = "gp3"
  }

  user_data = file("${path.module}/user-data/sonarqube.sh")

  tags = merge(local.common_tags, { Name = "${var.project_name}-sonarqube" })
}

# --- Kubernetes control plane ---
resource "aws_instance" "k8s_master" {
  ami                         = data.aws_ami.ubuntu_24_04.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.k8s.id]
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_base.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.disk_sizes_gb["k8s_master"]
    volume_type = "gp3"
  }

  # common.sh is concatenated ahead of the role-specific script so both
  # scripts can be maintained/read independently but still run as one
  # user-data payload.
  user_data = join("\n", [
    file("${path.module}/user-data/common.sh"),
    templatefile("${path.module}/user-data/kubernetes-master.sh", {
      aws_region     = var.aws_region
      ssm_param_name = local.ssm_join_command_param
      git_repo_url   = var.git_repo_url
    }),
  ])

  tags = merge(local.common_tags, { Name = "${var.project_name}-k8s-master" })
}

# --- Kubernetes workers ---
resource "aws_instance" "k8s_worker1" {
  ami                         = data.aws_ami.ubuntu_24_04.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.k8s.id]
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_base.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.disk_sizes_gb["k8s_worker1"]
    volume_type = "gp3"
  }

  user_data = join("\n", [
    file("${path.module}/user-data/common.sh"),
    templatefile("${path.module}/user-data/kubernetes-worker.sh", {
      master_private_ip = aws_instance.k8s_master.private_ip
      aws_region        = var.aws_region
      ssm_param_name    = local.ssm_join_command_param
    }),
  ])

  tags = merge(local.common_tags, { Name = "${var.project_name}-k8s-worker1" })

  depends_on = [aws_instance.k8s_master]
}

resource "aws_instance" "k8s_worker2" {
  ami                         = data.aws_ami.ubuntu_24_04.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.k8s.id]
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.ec2_base.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = var.disk_sizes_gb["k8s_worker2"]
    volume_type = "gp3"
  }

  user_data = join("\n", [
    file("${path.module}/user-data/common.sh"),
    templatefile("${path.module}/user-data/kubernetes-worker.sh", {
      master_private_ip = aws_instance.k8s_master.private_ip
      aws_region        = var.aws_region
      ssm_param_name    = local.ssm_join_command_param
    }),
  ])

  tags = merge(local.common_tags, { Name = "${var.project_name}-k8s-worker2" })

  depends_on = [aws_instance.k8s_master]
}
