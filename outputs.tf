output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "nginx_public_ip" {
  value = aws_instance.nginx.public_ip
}

output "nginx_private_ip" {
  value = aws_instance.nginx.private_ip
}

output "node1_private_ip" {
  value = aws_instance.node1.private_ip
}

output "node2_private_ip" {
  value = aws_instance.node2.private_ip
}

output "mysql_private_ip" {
  value = aws_instance.mysql.private_ip
}