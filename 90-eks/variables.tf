variable "project_name" {
  description = "Project name"
  type        = string
  default     = "roboshop"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "domain_name" {
  description = "Route53 domain name"
  type        = string
  default     = "eswar.xyz"
}

variable "zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
  default     = "Z00224221HVTOMR4RK7YI"
}

# Node group versions
variable "eks_nodegroup_blue_version" {
  description = "Kubernetes version for blue node group"
  type        = string
  default     = "1.32"
}

variable "eks_nodegroup_green_version" {
  description = "Kubernetes version for green node group"
  type        = string
  default     = "1.32"
}

# Enable flags (IMPORTANT 🔥)
variable "enable_blue" {
  description = "Enable blue node group"
  type        = bool
  default     = true
}

variable "enable_green" {
  description = "Enable green node group"
  type        = bool
  default     = false
}