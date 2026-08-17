# Modules should declare the providers they need. Version constraints are set
# by the root module; this only declares the requirement.
terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70"
    }
  }
}
