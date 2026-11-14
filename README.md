
Your README must let a reviewer run everything without guessing. Include:
1. Prerequisites and step-by-step instructions to run the app and the observability stack locally
with docker compose up, including how to access Grafana and the dashboards.

docker awscli terraform gh (optional), 

Report for each type of deployment and screenshots inside ./reports/
as:
...

Local dev:

1. For running the app locally
docker compose up, runs the app (default port 8080) 



2. Instructions for running the tests, the health script, the Terraform code, and the Kubernetes
deployment.

Github Repo Variables
AWS_REGION: aws region
EC2_INSTANCE_ID # ec2 instance id, found afrer terraform appy. 
ECR_REPOSITORY_NAME  #container registry repo name


env selection: staging, prod. 

terraform init -backend-config=envs/staging.backend.hcl
terraform plan -var-file=envs/staging.tfvars
terraform apply -var-file=envs/staging.tfvars

terraform destroy -var-file=envs/staging.tfvars


3. An architecture diagram covering Code Commit → CI (lint, test, scan) → Registry → Deployment
to EC2, along with the Kubernetes deployment flow and the observability stack (how metrics
and logs flow from the app and host into Grafana).
4. A Design Decisions section explaining key trade-offs (e.g. distroless vs Alpine, EC2 vs ECS vs
EKS, your tagging and secrets strategy, log label choices).

5. A Deployment & Rollback Strategy section: how a release reaches production safely, and
how you would roll back.



6. A Security Considerations section covering secrets management, image scanning, IAM, and
network exposure.

Used Github OIDC with AWS IAM with Least Privilege. 

Image scanning follows xxx, intentionally suppresses YY to ZZZ. 




7. A rough monthly AWS cost estimate for running this in production.

For ec2 based deployment,
estimated cost:
...

8. A What I would improve with more time section.

With more time, 
i would improve it by going through a checklist of testing and chaos engineering to 
push it's limit, calculate ~exact numbers of rps, limits, errors spikes and thorttling it on different percentile to get more detailed scenaiors how it will work under pressure and high load. 
Load balancing for different layers and similar...

9. A short note on whether and how you used AI tools during this task. Using them is allowed; we
only ask that you can explain every part of your submission.

Most of the code parts are generated using with deliberate instructions with task context. And, each part is hand checked, and reports generated are inside ./reports/ with codes for steps producing each. 
