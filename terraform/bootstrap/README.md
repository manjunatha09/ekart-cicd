# terraform/bootstrap

Creates the S3 bucket (+ DynamoDB lock table) used as the remote state
backend for `terraform/infrastructure`. Run this once, first.

```bash
cd terraform/bootstrap
terraform init
terraform apply
```

Copy the `state_bucket_name` and `lock_table_name` outputs into
`terraform/infrastructure/backend.tf`, then proceed to the infrastructure
directory.

This bootstrap project keeps its state locally (a local `terraform.tfstate`
file in this folder) — do not delete that file, and do not commit it to
Git. It's excluded via `.gitignore`.
