# Shared role/instance profile for all five EC2 instances. Used mainly for
# the SSM Parameter Store handoff that automates `kubeadm join`: the
# control plane writes the join command to a SecureString parameter, and
# each worker polls for it and runs it itself — no manual SSH round-trip
# needed. (Jenkins/Argo CD/kubectl otherwise still use credentials
# configured by hand or via Jenkins Credentials, not this role.)

resource "aws_iam_role" "ec2_base" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Scoped narrowly to the one parameter this project uses — not a blanket
# SSM permission.
resource "aws_iam_role_policy" "ssm_join_command" {
  name = "${var.project_name}-ssm-join-command"
  role = aws_iam_role.ec2_base.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter${local.ssm_join_command_param}"
      },
      {
        # SecureString parameters are encrypted with the account's default
        # aws/ssm KMS key; both the writer (master) and readers (workers)
        # need decrypt/generate-data-key on it.
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_base" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_base.name
}
