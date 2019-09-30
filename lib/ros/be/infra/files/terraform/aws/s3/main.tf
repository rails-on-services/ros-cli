resource "aws_s3_bucket" "this" {
  count = length(var.s3_bucket_names)
  bucket = var.s3_bucket_names[count.index]
  acl    = "private"
  tags = var.tags
}
