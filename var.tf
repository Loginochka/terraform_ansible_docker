variable "token" {
  sensitive   = true
}
variable "folder" {
  sensitive   = true
}
variable "cloud" {
  sensitive   = true
}
variable "pvt_key" {
  sensitive   = true
}
variable "pub_key" {
  sensitive   = true
}
variable "pvt_key_bst" {
  sensitive   = true
}
variable "pub_key_bst" {
  sensitive   = true
}
variable "server_name" {
  type    = list(string)
  default = ["vm-docker-1", "vm-docker-2", "vm-docker-3"]
}