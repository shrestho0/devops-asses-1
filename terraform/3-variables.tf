variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "app_name" {
  type    = string
  default = "devops-task"
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "ecr_repository_name" {
  type    = string
  default = "devops-task"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "architecture" {
  type    = string
  default = "x86_64" # use arm64 with a t4g.* instance type

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "root_volume_size" {
  type    = number
  default = 8
}

variable "initial_image_tag" {
  description = "Existing ECR tag (for example sha-abc...) started at first boot. Empty means CI deploys it."
  type        = string
  default     = ""
}