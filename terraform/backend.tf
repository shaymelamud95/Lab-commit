terraform {
  backend "s3" {
    bucket         = "tfstate-lab-commit-923337630273"
    key            = "lab-commit/terraform.tfstate"
    region         = "il-central-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
