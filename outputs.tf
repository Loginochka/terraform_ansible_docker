output "vm-docker" {
  value = tolist(yandex_compute_instance.vm-docker[*].network_interface.0.ip_address)
}
output "ALB" {
  value = {
    ALB = yandex_alb_load_balancer.alb-balancer.listener[0].endpoint[0].address[0].external_ipv4_address[0].address
  }
}
output "bastion_ip" {
  value = yandex_compute_instance.vm-bastion.network_interface[0].nat_ip_address  
}