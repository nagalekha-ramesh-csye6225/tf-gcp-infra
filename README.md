# tf-gcp-infra

My IaaC using Terraform for: [CYSE6225 Network Structures &amp; Cloud Computing](https://spring2024.csye6225.cloud/)

## GCP Networking Setup

1. VPC Network:
   - Disabled auto-create 
   - Regional routing mode
   - No default routes
2. Subnet #1: webapp
   - /24 CIDR range
3. Subnet #2: db
   - /24 CIDR range
4. Attached Internet Gateway to the VPC

## How to build & run the application

1. Clone this repository to your local machine.

2. Navigate to the directory containing the Terraform configuration files.

3. Update the `terraform.tfvars` file with your specific configurations:

   ```hcl
   service_account_file_path = "path/to/your/service-account-key.json"
   prj_id                    = "your-gcp-project-id"
   cloud_region              = "your-gcp-region"
   ```

4. Modify the VPC configurations in the `variables.tf` file as per your requirements:

5. Terraform Initalization
   
    ```
    terraform init
    ```

3. Terraform Validate
   
   ```
   terraform validate
   ```

4. Terraform Apply
   
   ```
   terraform apply
   ```

5. Cleanup
   To avoid incurring necessary charges, remember to destroy the Terraform-managed infrastructure when it's no longer needed
   
   ```
   terraform destroy
   ```

## Enabled GCP Service APIs

1. Compute Engine API
2. Cloud SQL Admin API
3. Cloud Storage JSON API
4. Cloud Logging API
5. Cloud Monitoring API
6. Identity and Access Management (IAM) API
7. Cloud DNS API
8. Cloud Build API
9. Service Networking API
10. Cloud Resource Manager API
11. Service Usage API

## Enabled following roles for Service Account
Using App Engine default Service Account
1. Cloud SQL Admin
2. Cloud SQL Client
3. Compute Network Admin
4. Compute Security Admin
5. Service Networking Admin
6. Service Networking Service Agent
7. Service Usage Admin

## References:
1. [Install Chocolatey](https://docs.chocolatey.org/en-us/choco/setup)
2. [Install Terraform using Chocolatey](https://community.chocolatey.org/packages/terraform)
3. [Set up Terraform](https://developer.hashicorp.com/terraform/install?ajs_aid=ee087ad3-951d-4cf7-bcf4-ebbe422dd887&product_intent=terraform)

