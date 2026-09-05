output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "sonarqube_public_ip" {
  value = aws_instance.sonarqube.public_ip
}

output "k8s_master_public_ip" {
  value = aws_instance.k8s_master.public_ip
}

output "k8s_worker1_public_ip" {
  value = aws_instance.k8s_worker1.public_ip
}

output "k8s_worker2_public_ip" {
  value = aws_instance.k8s_worker2.public_ip
}

output "app_url" {
  description = "Stable URL for the app, via the Network Load Balancer in front of both workers"
  value       = "http://${aws_lb.ekart.dns_name}"
}

output "ssh_examples" {
  value = <<-EOT
    ssh -i awspem.pem ubuntu@${aws_instance.jenkins.public_ip}      # Jenkins
    ssh -i awspem.pem ubuntu@${aws_instance.sonarqube.public_ip}    # SonarQube
    ssh -i awspem.pem ubuntu@${aws_instance.k8s_master.public_ip}   # K8s master
    ssh -i awspem.pem ubuntu@${aws_instance.k8s_worker1.public_ip}  # K8s worker 1
    ssh -i awspem.pem ubuntu@${aws_instance.k8s_worker2.public_ip}  # K8s worker 2
  EOT
}
