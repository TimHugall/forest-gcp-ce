# forest-gcp-ce
Creates a Dedicated server for the Forest

## Instructions

1. Clone repo
2. Create project and bucket for backend state and modify `backend.tf` and `versions.tf` accordingly
3. **TODO** Uploading existing saves
4. If using Route53 ensure your AWS CLI credentials are correct
5. Create a `terraform.tfvars` file to specify your desired values for variables
6. `gcloud init`
7. `gcloud auth` etc
8. `terraform init && terraform apply`

## TODO
- Use service account with more fine-grained IAM permissions for instance