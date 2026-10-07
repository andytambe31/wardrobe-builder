terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.40" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }

  # Partial backend — real values come from backend.hcl:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}
