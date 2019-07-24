output "ec2" {
  value = aws_instance.this
}

output "lb" {
  value = aws_lb.this
}

output "eip" {
  value = aws_eip.this
}
