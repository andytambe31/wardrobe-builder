terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
  # Bootstrap uses LOCAL state on purpose — it *creates* the remote-state
  # backend (S3 bucket + DynamoDB lock) that every other stack then uses.
  # Commit the resulting bootstrap/terraform.tfstate is optional; it only holds
  # the state bucket + OIDC role, and is easy to re-import.
}
