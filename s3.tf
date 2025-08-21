resource "aws_s3_bucket" "buckets" {
  for_each = local.buckets
  bucket   = each.key
}
