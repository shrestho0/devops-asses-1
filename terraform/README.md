## 1. Setting up the infra

terraform init -backend-config=envs/staging.backend.hcl
terraform plan -var-file=envs/staging.tfvars
terraform apply -var-file=envs/staging.tfvars

root@localhost:~/devops-asses-1/terraform# gh variable list
NAME                 VALUE                UPDATED               
AWS_REGION           us-east-2            about 22 hours ago
EC2_INSTANCE_ID      i-09a5596eb84969362  less than a minute ago
ECR_REPOSITORY_NAME  devops-task          about 22 hours ago

root@localhost:~/devops-asses-1/terraform# gh secret list
NAME               UPDATED           
AWS_OIDC_ROLE_ARN  about 22 hours ago
root@localhost:~/devops-asses-1/terraform# 


## 2. Deployment

Create pr or push to main. 

## 3. Rollback check