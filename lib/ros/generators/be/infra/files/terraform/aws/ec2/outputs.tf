output "this" {
  value = aws_instance.this
}

output "lb" {
  value = aws_lb.this
}

output "eip" {
  value = aws_eip.this
}

output "lb_route53_record" {
  value = aws_route53_record.lb
}
