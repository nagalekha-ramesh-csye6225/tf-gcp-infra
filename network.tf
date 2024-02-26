provider "google" {
  credentials = file(var.service_account_file_path)
  project     = var.project_id
  region      = var.region
}

resource "google_compute_network" "vpc" {
  count                           = length(var.vpcs)
  name                            = var.vpcs[count.index].vpc_name
  auto_create_subnetworks         = var.vpcs[count.index].auto_create_subnetworks
  routing_mode                    = var.vpcs[count.index].routing_mode
  delete_default_routes_on_create = var.vpcs[count.index].delete_default_routes_on_create
}

resource "google_compute_subnetwork" "webapp" {
  count         = length(var.vpcs)
  name          = var.vpcs[count.index].webapp_subnet_name
  ip_cidr_range = var.vpcs[count.index].webapp_subnet_cidr
  network       = google_compute_network.vpc[count.index].self_link
  region        = var.region
}

resource "google_compute_subnetwork" "db" {
  count         = length(var.vpcs)
  name          = var.vpcs[count.index].db_subnet_name
  ip_cidr_range = var.vpcs[count.index].db_subnet_cidr
  network       = google_compute_network.vpc[count.index].self_link
  region        = var.region
}

resource "google_compute_route" "webapp_route" {
  count            = length(var.vpcs)
  name             = "webapp-route-${count.index}"
  network          = google_compute_network.vpc[count.index].self_link
  dest_range       = var.vpcs[count.index].dest_range
  next_hop_gateway = var.vpcs[count.index].next_hop_gateway
}

resource "google_compute_firewall" "allow_8080" {
  count   = length(var.vpcs)
  name    = "allow-8080-${count.index}"
  network = google_compute_network.vpc[count.index].name

  allow {
    protocol = var.vpcs[count.index].protocol
    ports    = var.vpcs[count.index].http_ports
  }

  source_ranges = var.vpcs[count.index].ssh_source_ranges
  target_tags   = var.vpcs[count.index].instance_tags

  priority = 1000
}

resource "google_compute_firewall" "deny_all" {
  count   = length(var.vpcs)
  name    = "deny-all-${count.index}"
  network = google_compute_network.vpc[count.index].name

  allow {
    protocol = "all"
    ports    = []
  }

  source_ranges = var.vpcs[count.index].ssh_source_ranges
  target_tags   = var.vpcs[count.index].instance_tags

  priority = 2000
}

resource "google_compute_instance" "webapp_instance" {
  count        = length(var.vpcs)
  name         = "webapp-instance-${count.index}"
  machine_type = var.vpcs[count.index].machine_type
  zone         = var.vpcs[count.index].zone

  boot_disk {
    initialize_params {
      image = var.vpcs[count.index].boot_disk_image_name
      type  = var.vpcs[count.index].boot_disk_type
      size  = var.vpcs[count.index].boot_disk_size
    }
  }

  network_interface {
    network    = google_compute_network.vpc[count.index].self_link
    subnetwork = google_compute_subnetwork.webapp[count.index].self_link
    access_config {}
  }
  tags       = var.vpcs[count.index].instance_tags
  depends_on = [google_compute_subnetwork.webapp, google_compute_firewall.allow_8080, google_compute_firewall.deny_all]

}

variable "service_account_file_path" {
  description = "Filepath of service-account-key.json"
  type        = string
}

variable "project_id" {
  description = "The ID of the GCP project"
  type        = string
}

variable "region" {
  description = "The GCP region to create resources in"
  type        = string
}

variable "vpcs" {
  description = "List of configurations for multiple VPCs"
  type = list(object({
    vpc_name                        = string
    webapp_subnet_name              = string
    webapp_subnet_cidr              = string
    db_subnet_name                  = string
    db_subnet_cidr                  = string
    routing_mode                    = string
    dest_range                      = string
    auto_create_subnetworks         = bool
    delete_default_routes_on_create = bool
    next_hop_gateway                = string
    protocol                        = string
    http_ports                      = list(string)
    ssh_source_ranges               = list(string)
    instance_tags                   = list(string)
    machine_type                    = string
    zone                            = string
    boot_disk_image_name            = string
    boot_disk_type                  = string
    boot_disk_size                  = number
  }))
  default = []
}