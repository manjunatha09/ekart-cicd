# Fill these in with the outputs from `terraform/bootstrap` after you've
# applied it once. Terraform does not allow variables inside a backend
# block, so these values must be hard-coded here.

terraform {
  backend "s3" {
    bucket         = "REPLACE_WITH_state_bucket_name_OUTPUT"
    key            = "ekart-cicd/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-lock-ekart-cicd"
    encrypt        = true
  }
}
