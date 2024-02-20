provider "google" {
  credentials = file(var.service_account_file_path)
  project     = var.project_id
  region      = var.region


resource "google_compute_network" "vpc" {
  count                   = length(var.vpcs)
  name                    = var.vpcs[count.index].vpc_name
  auto_create_subnetworks = var.vpcs[count.index].auto_create_subnetworks
  routing_mode            = var.vpcs[count.index].routing_mode
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
  count              = length(var.vpcs)
  name               = "webapp-route-${count.index}"
  network            = google_compute_network.vpc[count.index].self_link
  dest_range         = var.vpcs[count.index].dest_range
  next_hop_gateway   = var.vpcs[count.index].next_hop_gateway
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
  type        = list(object({
    vpc_name             = string
    webapp_subnet_name   = string
    webapp_subnet_cidr   = string
    db_subnet_name       = string
    db_subnet_cidr       = string
    routing_mode         = string
    dest_range           = string
    auto_create_subnetworks      = bool
    delete_default_routes_on_create = bool
    next_hop_gateway     = string
  }))
  default = []
}
