#______________Provider________________________________
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}
provider "yandex" {
  zone      = "ru-central1-a"
  token     = var.token
  cloud_id  = var.cloud
  folder_id = var.folder
}
#______________Instance___________________________
resource "yandex_compute_instance" "vm-docker" {
  count = 3
  name               = var.server_name[count.index]
  platform_id        = "standard-v1"
  allow_stopping_for_update = true
  zone               = "ru-central1-a"
  folder_id          = var.folder
  hostname           = "ru-${var.server_name[count.index]}.local"
  resources {
    cores  = 2
    memory = 2
    core_fraction = 20
  }

  boot_disk {
    mode = "READ_WRITE"
    initialize_params {
      image_id = "fd8hnnsnfn3v88bk0k1o"
      size     = 20
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private-a.id
    security_group_ids = [yandex_vpc_security_group.docker-host.id]
  }

  metadata = {
    user-data = file("meta-vm.txt")
  }
  scheduling_policy {
    preemptible = true
  }
  timeouts {
    create = "60m"
  }
}
resource "yandex_compute_instance" "vm-bastion" {
  name               = "vm-bastion"
  platform_id        = "standard-v1"
  allow_stopping_for_update = true
  zone               = "ru-central1-a"
  folder_id          = var.folder
  hostname           = "ru-bst-b.local"
  resources {
    cores  = 2
    memory = 2
    core_fraction = 20
  }

  boot_disk {
    mode = "READ_WRITE"
    initialize_params {
      image_id = "fd8hnnsnfn3v88bk0k1o"
      size     = 20
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private-a.id
    security_group_ids = [yandex_vpc_security_group.bastion-host.id]
    nat                = "true"

  }

  metadata = {
    user-data = file("meta.txt")
  }
  scheduling_policy {
    preemptible = true
  }
  timeouts {
    create = "60m"
  }
}
resource "null_resource" "ansible_exec" {
  depends_on = [ local_file.inventory ]
  provisioner "local-exec" {
    command = "sleep 40; ansible-playbook -i ansible/inventory ansible/docker.yaml"
  } # Sleep in 40 sec for ssh start up
}
#_______________ALB________________________________
resource "yandex_alb_target_group" "web-server-tg" {
  name = "web-server-tg"

  dynamic "target" {
    for_each = yandex_compute_instance.vm-docker
    content {
      subnet_id  = yandex_vpc_subnet.private-a.id
      ip_address = target.value.network_interface.0.ip_address
    }
  }
}
resource "yandex_alb_http_router" "web-router" {
  name = "web-router"
}
resource "yandex_alb_virtual_host" "vh-for-web" {
  name           = "web-vh"
  http_router_id = yandex_alb_http_router.web-router.id
  route {
    name = "web"
    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.web-backend-group.id
        timeout          = "60s"
      }
    }
  }
}
resource "yandex_alb_backend_group" "web-backend-group" {
  name = "web-backend-group"
  http_backend {
    name             = "web-http-backend"
    weight           = "1"
    port             = "8090"
    target_group_ids = ["${yandex_alb_target_group.web-server-tg.id}"]
    load_balancing_config {
      panic_threshold = 50
      mode            = "ROUND_ROBIN"
    }
    healthcheck {
      timeout  = "15s"
      interval = "60s"
      http_healthcheck {
        path = "/"
      }
    }
  }
}
resource "yandex_alb_load_balancer" "alb-balancer" {
  depends_on = [ null_resource.ansible_exec ]
  name               = "alb-balancer"
  network_id         = yandex_vpc_network.cod.id
  security_group_ids = ["${yandex_vpc_security_group.ALB.id}", "${yandex_vpc_security_group.docker-host.id}"]
  allocation_policy {
    location {
      zone_id   = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.private-a.id
    }
  }

  listener {
    name = "alb-listener"
    endpoint {
      address {
        external_ipv4_address {
        }
      }
      ports = ["8090"]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.web-router.id
      }
    }
  }
  log_options {
    discard_rule {
      http_code_intervals = ["HTTP_2XX"]
      discard_percent     = 75
    }
  }
}
#________________NETWORK_______________________
resource "yandex_vpc_network" "cod" {
  name = "cod"
}
resource "yandex_vpc_subnet" "private-a" {
  name           = "private-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.cod.id
  v4_cidr_blocks = ["10.10.10.0/28"]
  route_table_id = yandex_vpc_route_table.route-table.id
}
resource "yandex_vpc_gateway" "nat-gateway" {
  folder_id = var.folder
  name      = "nat-gateway"
  shared_egress_gateway {}
}
resource "yandex_vpc_route_table" "route-table" {
  folder_id  = var.folder
  name       = "route-table"
  network_id = yandex_vpc_network.cod.id
  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat-gateway.id
  }
}
resource "yandex_vpc_security_group" "bastion-host" {
  network_id = yandex_vpc_network.cod.id
  name       = "Bastion host via SSH"
  ingress {
    protocol       = "TCP"
    port           = "22"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol       = "TCP"
    port           = "22"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "yandex_vpc_security_group" "docker-host" {
  network_id = yandex_vpc_network.cod.id
  name       = "Docker host's"
  ingress {
    protocol       = "TCP"
    port           = "22"
    security_group_id = yandex_vpc_security_group.bastion-host.id
  }
  ingress {
    protocol    = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "local_file" "inventory" {
  content = templatefile("ansible/inventory.tmpl", {
    vm_docker = [for instance in yandex_compute_instance.vm-docker : instance.network_interface[0].ip_address]
    bastion_ip = yandex_compute_instance.vm-bastion.network_interface[0].nat_ip_address
    worker = yandex_compute_instance.vm-docker[0].network_interface[0].ip_address
  })
  filename = "ansible/inventory"
}
resource "yandex_vpc_security_group" "ALB" {
  network_id = yandex_vpc_network.cod.id
  name = "ALB security group"
  ingress {
    protocol = "ANY"
    port = 8090
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
