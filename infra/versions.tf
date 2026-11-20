terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.x breaks aws_s3_bucket against the local emulator.
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region            = var.aws_region
  s3_use_path_style = var.s3_use_path_style

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
