variable "name" {
  description = "Repository name."
  type        = string
}

variable "keep_last_images" {
  description = "Number of most recent images to keep."
  type        = number
  default     = 20
}

variable "force_delete" {
  description = "Allow deleting the repository while it still holds images."
  type        = bool
  default     = false
}
