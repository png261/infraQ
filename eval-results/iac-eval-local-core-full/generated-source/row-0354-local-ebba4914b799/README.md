# Aurora MySQL with RDS Proxy

Minimal AWS Terraform/OpenTofu configuration for an Aurora MySQL cluster fronted by an RDS DB proxy in `us-east-1`.

## Validation

```bash
terraform init
terraform validate
terraform plan -var='db_master_password=REPLACE_WITH_STRONG_PASSWORD'
```

Do not apply this benchmark configuration unless you have reviewed the plan and costs.

## Secret handling note

This benchmark intentionally includes `aws_secretsmanager_secret_version` so the RDS proxy can authenticate with Secrets Manager. Terraform/OpenTofu marks the password variable as sensitive, but the secret value is still stored in state. Use encrypted, access-controlled remote state for real deployments.
