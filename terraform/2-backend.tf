terraform {
  backend "s3" {
    bucket       = "devops-task-tfstate-819379976470"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
    # key is passed per environment: -backend-config=envs/<env>.backend.hcl
  }
}