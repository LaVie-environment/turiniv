output "web_instance_ip" {
    value = aws_instance.uat_env.public_ip
}