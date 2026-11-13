variable "name_prefix" {
  description = "Prefix for resource names, usually <project>-<env>."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC. Public subnets are carved out of it."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread subnets over."
  type        = number
  default     = 2
}
