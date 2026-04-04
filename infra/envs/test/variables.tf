variable "project" {
  description = "Short project name used in resource names (lowercase, no spaces). Change this when forking."
  type        = string
  default     = "agfactory"
}

variable "environment" {
  description = "Deployment environment (dev | test | prod)"
  type        = string
  default     = "test"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default     = {}
}
