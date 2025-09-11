terraform {
  backend "s3" {
    bucket       = "kenielf-terraform"
    key          = "terraform/tfstate"
    region       = "us-east-1"
    profile      = "terraform"
    use_lockfile = true
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "terraform"
  default_tags {
    tags = { Owner = "terraform", Backup = "false", client = var.client }
  }
}

resource "aws_s3_bucket" "terraform" {
  bucket              = "${var.client}-terraform"
  object_lock_enabled = true
  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}

resource "aws_s3_bucket_ownership_controls" "terraform_ownership" {
  bucket = aws_s3_bucket.terraform.id
  rule { object_ownership = "BucketOwnerPreferred" }
  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}

resource "aws_s3_bucket_acl" "terraform_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.terraform_ownership]
  bucket     = aws_s3_bucket.terraform.id
  acl        = "private"
  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}
