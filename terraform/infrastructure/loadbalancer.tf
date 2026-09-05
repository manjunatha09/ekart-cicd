# loadbalancer.tf
#
# This is a self-managed kubeadm cluster on plain EC2 — there is no AWS
# cloud-controller-manager wired up, so Kubernetes' own `type: LoadBalancer`
# Service would just sit in "Pending" forever (it needs the ccm + IAM +
# subnet tagging to actually call the AWS API). Wiring that up is a lot of
# extra moving parts for a lab.
#
# The standard alternative for self-managed clusters: keep the Kubernetes
# Service as NodePort (kubernetes/service.yaml, nodePort 30070) and put a
# real AWS Network Load Balancer in front of the worker nodes ourselves,
# targeting that NodePort on both of them. That's what this file does.
#
# Result: one stable DNS name / IP in front of both workers, instead of
# hitting a single worker's public IP directly. If a worker is replaced,
# update the target group attachment (or move to an Auto Scaling Group
# later) rather than changing any URL you've shared.

resource "aws_lb" "ekart" {
  name               = "${var.project_name}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.public.id]

  tags = merge(local.common_tags, { Name = "${var.project_name}-nlb" })
}

resource "aws_lb_target_group" "ekart_app" {
  name        = "${var.project_name}-app-tg"
  port        = 30070 # must match kubernetes/service.yaml's nodePort
  protocol    = "TCP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    protocol            = "HTTP"
    path                = "/actuator/health"
    port                = "30070"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 10
  }

  tags = merge(local.common_tags, { Name = "${var.project_name}-app-tg" })
}

resource "aws_lb_target_group_attachment" "worker1" {
  target_group_arn = aws_lb_target_group.ekart_app.arn
  target_id        = aws_instance.k8s_worker1.id
  port             = 30070
}

resource "aws_lb_target_group_attachment" "worker2" {
  target_group_arn = aws_lb_target_group.ekart_app.arn
  target_id        = aws_instance.k8s_worker2.id
  port             = 30070
}

resource "aws_lb_listener" "ekart_app" {
  load_balancer_arn = aws_lb.ekart.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ekart_app.arn
  }
}
