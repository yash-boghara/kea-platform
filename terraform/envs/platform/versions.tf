terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
  }

  # Created manually once, in Phase 0. Chicken-and-egg: the state backend
  # cannot itself live in the state it backs.
  backend "s3" {
    bucket         = "CHANGEME-tfstate"
    key            = "platform/terraform.tfstate"
    region         = "ap-southeast-2"
    dynamodb_table = "CHANGEME-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  # default_tags is how the tagging policy gets satisfied everywhere at once,
  # rather than by remembering to tag each resource. Policy plus a good default
  # beats policy alone.
  default_tags {
    tags = local.tags
  }
}

locals {
  name = "kea-platform"

  tags = {
    Owner              = "yash"
    Environment        = "platform"
    CostCentre         = "portfolio-001"
    DataClassification = "internal"
    ManagedBy          = "terraform"
    Repo               = "kea"
  }
}
