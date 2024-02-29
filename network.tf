provider "google" {
  credentials = file(var.service_account_file_path)
  project     = var.project_id
}

resource "google_compute_network" "vpc" {
  count                           = length(var.vpcs)
  name                            = var.vpcs[count.index].vpc_name
  auto_create_subnetworks         = var.vpcs[count.index].auto_create_subnetworks
  routing_mode                    = var.vpcs[count.index].routing_mode
  delete_default_routes_on_create = var.vpcs[count.index].delete_default_routes_on_create
}

resource "google_compute_subnetwork" "webapp" {
  count                    = length(var.vpcs)
  name                     = var.vpcs[count.index].webapp_subnet_name
  ip_cidr_range            = var.vpcs[count.index].webapp_subnet_cidr
  network                  = google_compute_network.vpc[count.index].self_link
  region                   = var.vpcs[count.index].region
  private_ip_google_access = var.vpcs[count.index].private_ip_google_access_webapp_subnet
}

resource "google_compute_subnetwork" "db" {
  count                    = length(var.vpcs)
  name                     = var.vpcs[count.index].db_subnet_name
  ip_cidr_range            = var.vpcs[count.index].db_subnet_cidr
  network                  = google_compute_network.vpc[count.index].self_link
  region                   = var.vpcs[count.index].region
  private_ip_google_access = var.vpcs[count.index].private_ip_google_access_db_subnet
}

resource "google_compute_route" "webapp_route" {
  count            = length(var.vpcs)
  name             = "webapp-route-${count.index}"
  network          = google_compute_network.vpc[count.index].self_link
  dest_range       = var.vpcs[count.index].dest_range
  next_hop_gateway = var.vpcs[count.index].next_hop_gateway
}

resource "google_compute_global_address" "private_ip_address" {
  count         = length(var.vpcs)
  name          = "private-ip-address-${count.index}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = google_compute_network.vpc[count.index].self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  count                   = length(var.vpcs)
  network                 = google_compute_network.vpc[count.index].self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address[count.index].name]
  depends_on              = [google_compute_network.vpc]
  deletion_policy         = "ABANDON"
}

resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "cloud_sql_instance" {

  count            = length(var.vpcs)
  name             = "private-sql-instance-${random_id.db_name_suffix.hex}"
  region           = var.vpcs[count.index].region
  database_version = var.vpcs[count.index].postgres_database_version
  # root_password       = var.vpcs[count.index].postgres_root_password
  deletion_protection = var.vpcs[count.index].cloud_sql_instance_deletion_protection

  depends_on = [google_service_networking_connection.private_vpc_connection, google_compute_network.vpc]

  settings {
    tier              = "db-f1-micro"
    availability_type = var.vpcs[count.index].cloud_sql_instance_availability_type
    disk_type         = var.vpcs[count.index].cloud_sql_instance_disk_type
    disk_size         = var.vpcs[count.index].cloud_sql_instance_disk_size
    ip_configuration {
      ipv4_enabled                                  = var.vpcs[count.index].ipv4_enabled
      private_network                               = google_compute_network.vpc[count.index].self_link
      enable_private_path_for_google_cloud_services = true
    }
  }
}

# Creating Cloud SQL database as per guidelines
resource "google_sql_database" "webapp_db" {
  count    = length(var.vpcs)
  name     = "webapp-db-${count.index}"
  instance = google_sql_database_instance.cloud_sql_instance[count.index].name
}

# Cloud SQL database user as per guidelines
resource "google_sql_user" "webapp_user" {
  count    = length(var.vpcs)
  name     = "webapp-user-${count.index}"
  instance = google_sql_database_instance.cloud_sql_instance[count.index].name
  password = random_password.webapp_db_password.result
}

# Generating random password for the user
resource "random_password" "webapp_db_password" {
  length  = 10
  special = true
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

  priority = var.vpcs[count.index].allow_8080_priority
}

resource "google_compute_firewall" "deny_all" {
  count   = length(var.vpcs)
  name    = "deny-all-${count.index}"
  network = google_compute_network.vpc[count.index].name

  deny {
    protocol = "all"
    ports    = []
  }

  source_ranges = var.vpcs[count.index].ssh_source_ranges
  target_tags   = var.vpcs[count.index].instance_tags

  priority = var.vpcs[count.index].deny_all_priority
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
  depends_on = [google_compute_subnetwork.webapp, google_compute_subnetwork.db, google_compute_firewall.allow_8080, google_compute_firewall.deny_all, google_sql_user.webapp_user, google_sql_database.webapp_db]

  metadata = {
    startup-script = <<-EOT
#!/bin/bash
set -e
sudo touch /opt/csye6225/webapp/.env

sudo echo "PORT=${var.env_port}" > /opt/csye6225/webapp/.env
sudo echo "DATABASE_NAME=${var.vpcs[count.index].database_name}" >> /opt/csye6225/webapp/.env
sudo echo "DATABASE_USERNAME=${var.vpcs[count.index].database_user_name}" >> /opt/csye6225/webapp/.env
sudo echo "DATABASE_PASSWORD=${random_password.webapp_db_password.result}" >> /opt/csye6225/webapp/.env
sudo echo "DATABASE_HOST=${google_sql_database_instance.cloud_sql_instance[count.index].private_ip_address}" >> /opt/csye6225/webapp/.env
sudo echo "DATABASE_DIALECT=${var.env_db_dialect}" >> /opt/csye6225/webapp/.env
sudo echo "DROP_DATABASE=${var.env_db_drop_db}" >> /opt/csye6225/webapp/.env

sudo systemctl restart webapp

sudo systemctl daemon-reload
EOT
  }

}

variable "service_account_file_path" {
  description = "Filepath of service-account-key.json"
  type        = string
}

variable "project_id" {
  description = "The ID of the GCP project"
  type        = string
}

variable "vpcs" {
  description = "List of configurations for multiple VPCs"
  type = list(object({
    region                                 = string
    vpc_name                               = string
    webapp_subnet_name                     = string
    webapp_subnet_cidr                     = string
    db_subnet_name                         = string
    db_subnet_cidr                         = string
    routing_mode                           = string
    dest_range                             = string
    auto_create_subnetworks                = bool
    delete_default_routes_on_create        = bool
    next_hop_gateway                       = string
    protocol                               = string
    http_ports                             = list(string)
    ssh_source_ranges                      = list(string)
    instance_tags                          = list(string)
    machine_type                           = string
    zone                                   = string
    boot_disk_image_name                   = string
    boot_disk_type                         = string
    boot_disk_size                         = number
    allow_8080_priority                    = number
    deny_all_priority                      = number
    private_ip_google_access_webapp_subnet = bool
    private_ip_google_access_db_subnet     = bool
    postgres_database_version              = string
    postgres_root_password                 = string
    cloud_sql_instance_deletion_protection = bool
    ipv4_enabled                           = bool
    cloud_sql_instance_availability_type   = string
    cloud_sql_instance_disk_type           = string
    cloud_sql_instance_disk_size           = number
    database_name                          = string
    database_user_name                     = string

  }))
  default = []
}

variable "env_port" {
  description = "ENV port"
  type        = string
}

variable "env_db_dialect" {
  description = "ENV DB dialect"
  type        = string
}

variable "env_db_drop_db" {
  description = "ENV Drop DB"
  type        = bool
}

