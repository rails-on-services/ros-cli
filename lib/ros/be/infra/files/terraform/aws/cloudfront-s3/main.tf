provider "aws" {
  region  = "us-east-1"
  profile = var.aws_profile
  alias   = "us-east-1"
}

resource "aws_s3_bucket" "this" {
  bucket = var.s3_bucket_name
  acl    = "private"

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    max_age_seconds = 1800
  }

  tags = var.tags
}

locals {
  s3_origin_id = "S3-${var.s3_bucket_name}"
}

resource "aws_acm_certificate" "cert" {
  provider          = aws.us-east-1
  count             = var.create_acm_certificate ? 1 : 0
  domain_name       = var.cloudfront_cname
  validation_method = "DNS"
  tags              = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  count   = var.create_acm_certificate ? 1 : 0
  name    = aws_acm_certificate.cert.0.domain_validation_options.0.resource_record_name
  type    = aws_acm_certificate.cert.0.domain_validation_options.0.resource_record_type
  zone_id = var.route53_zone_id
  records = [aws_acm_certificate.cert.0.domain_validation_options.0.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert" {
  provider                = aws.us-east-1
  count                   = var.create_acm_certificate ? 1 : 0
  certificate_arn         = aws_acm_certificate.cert.0.arn
  validation_record_fqdns = aws_route53_record.cert_validation[*].fqdn
}

locals {
  acm_certificate_arn = var.create_acm_certificate ? "${aws_acm_certificate.cert.0.arn}" : var.acm_certificate_arn
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = var.acm_certificate_arn
}

data "aws_iam_policy_document" "origin" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::$${bucket_name}$${origin_path}*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::$${bucket_name}"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
    }
  }
}

data "template_file" "aws_iam_policy_document" {
  template = data.aws_iam_policy_document.origin.json

  vars = {
    bucket_name = var.s3_bucket_name
    origin_path = "/"
  }
}

resource "aws_s3_bucket_policy" "this" {
  depends_on = [aws_s3_bucket.this]
  bucket     = var.s3_bucket_name
  policy     = data.template_file.aws_iam_policy_document.rendered
}

resource "aws_cloudfront_distribution" "this" {
  depends_on = [aws_acm_certificate_validation.cert]

  origin {
    domain_name = aws_s3_bucket.this.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled         = true
  is_ipv6_enabled = true
  comment         = var.cloudfront_cname

  aliases = [var.cloudfront_cname]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false
      headers = [
        "Access-Control-Request-Headers",
        "Access-Control-Request-Method",
        "Origin",
      ]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  tags = var.tags

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = local.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.1_2016"
  }
}

resource "aws_route53_record" "cloudfront" {
  name    = var.cloudfront_cname
  type    = "A"
  zone_id = var.route53_zone_id
  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
