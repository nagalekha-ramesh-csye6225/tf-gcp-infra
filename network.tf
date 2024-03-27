provider "google" {
  credentials = file(var.service_account_file_path)
  project     = var.project_id
}

resource "google_service_account" "service_account" {
  account_id                   = var.service_account.account_id
  display_name                 = var.service_account.display_name
  create_ignore_already_exists = var.service_account.create_ignore_already_exists
}

resource "google_project_iam_binding" "service_account_logging_admin" {
  project = var.project_id
  role    = var.roles.logging_admin_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
}

resource "google_project_iam_binding" "service_account_monitoring_metric_writer" {
  project = var.project_id
  role    = var.roles.monitoring_metric_writer_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
}

resource "google_project_iam_binding" "service_account_pubsub_publisher" {
  project = var.project_id
  role    = var.roles.pubsub_publisher_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
}

resource "google_pubsub_topic_iam_binding" "verify_email_topic_binding" {
  project = google_pubsub_topic.verify_email_topic.project
  topic   = google_pubsub_topic.verify_email_topic.name
  role    = var.roles.pubsub_publisher_role
  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account, google_pubsub_topic.verify_email_topic]
}

resource "google_project_iam_binding" "service_account_token_creator_role" {
  project = var.project_id
  role    = var.roles.service_account_token_creator_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
}

resource "google_project_iam_binding" "cloud_functions_developer_role" {
  project = var.project_id
  role    = var.roles.cloud_functions_developer_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
}

resource "google_project_iam_binding" "cloud_run_invoker_role" {
  project = var.project_id
  role    = var.roles.cloud_run_invoker_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
}

resource "google_compute_network" "vpc" {
  count                           = var.replica
  name                            = "${var.vpc.name}-${count.index}"
  auto_create_subnetworks         = var.vpc.auto_create_subnetworks
  routing_mode                    = var.vpc.routing_mode
  delete_default_routes_on_create = var.vpc.delete_default_routes
}

resource "google_compute_subnetwork" "webapp" {
  count         = var.replica
  name          = "${var.vpc_subnet_webapp.name}-${count.index}"
  ip_cidr_range = var.vpc_subnet_webapp.ip_cidr_range
  network       = google_compute_network.vpc[count.index].self_link
  region        = var.region

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_subnetwork" "db" {
  count                    = var.replica
  name                     = "${var.vpc_subnet_db.name}-${count.index}"
  ip_cidr_range            = var.vpc_subnet_db.ip_cidr_range
  network                  = google_compute_network.vpc[count.index].self_link
  region                   = var.region
  private_ip_google_access = var.vpc_subnet_db.enable_private_ip_google_access

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_route" "webapp_route" {
  count            = var.replica
  name             = "${var.vpc_webapp_route.name}-${count.index}-route"
  network          = google_compute_network.vpc[count.index].self_link
  dest_range       = var.vpc_webapp_route.dest_range
  next_hop_gateway = var.vpc_webapp_route.next_hop_gateway

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_global_address" "private_ip_address" {
  count         = var.replica
  name          = "${var.private_ip_address.name}-${count.index}"
  address_type  = var.private_ip_address.global_address_address_type
  purpose       = var.private_ip_address.global_address_purpose
  network       = google_compute_network.vpc[count.index].self_link
  prefix_length = var.private_ip_address.global_address_prefix_length

  depends_on = [google_compute_network.vpc]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  count                   = var.replica
  network                 = google_compute_network.vpc[count.index].self_link
  service                 = var.private_vpc_connection.google_service_nw_connection_service
  reserved_peering_ranges = [google_compute_global_address.private_ip_address[count.index].name]

  depends_on = [google_compute_network.vpc, google_compute_global_address.private_ip_address]
}

resource "google_vpc_access_connector" "serverless_connector" {
  count          = var.replica
  name           = "${var.serverless_vpc_access.name}-${count.index}"
  ip_cidr_range  = var.serverless_vpc_access.ip_cidr_range
  network        = google_compute_network.vpc[count.index].self_link
  machine_type   = var.serverless_vpc_access.machine_type
  min_instances  = var.serverless_vpc_access.minimum_instances
  max_instances  = var.serverless_vpc_access.maximum_instances
  max_throughput = var.serverless_vpc_access.maximum_throughput
  region         = var.region

  depends_on = [google_compute_network.vpc, google_service_networking_connection.private_vpc_connection]
}
resource "google_compute_firewall" "allow_iap" {
  count   = var.replica
  name    = "allow-iap-${count.index}"
  network = google_compute_network.vpc[count.index].name

  allow {
    protocol = var.firewall_allow.firewall_allow_protocol
    ports    = var.firewall_allow.firewall_allow_ports
  }

  source_ranges = [var.vpc_webapp_route.dest_range]
  target_tags   = [var.compute_engine.compute_engine_webapp_tag]

  priority = var.firewall_allow.firewall_allow_priority

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_firewall" "deny_all" {
  count   = var.replica
  name    = "deny-all-${count.index}"
  network = google_compute_network.vpc[count.index].name

  deny {
    protocol = "all"
  }

  source_ranges = [var.vpc_webapp_route.dest_range]
  target_tags   = [var.compute_engine.compute_engine_webapp_tag]

  priority = var.firewall_deny.firewall_deny_priority

  depends_on = [google_compute_network.vpc]
}

resource "google_dns_record_set" "dns_record" {
  count        = var.replica
  name         = var.dns_record.domain_name
  managed_zone = var.dns_record.managed_zone_dns_name
  ttl          = var.dns_record.ttl
  type         = var.dns_record.type
  rrdatas      = [google_compute_instance.webapp_instance[count.index].network_interface[0].access_config[0].nat_ip]


  depends_on = [google_compute_instance.webapp_instance]
}

resource "google_compute_instance" "webapp_instance" {
  count        = var.replica
  name         = "webapp-instance-${count.index}"
  machine_type = var.compute_engine.compute_engine_machine_type
  zone         = var.compute_engine.compute_engine_machine_zone

  boot_disk {
    initialize_params {
      image = var.compute_engine.boot_disk_image
      type  = var.compute_engine.boot_disk_type
      size  = var.compute_engine.boot_disk_size
    }
  }

  network_interface {
    network    = google_compute_network.vpc[count.index].self_link
    subnetwork = google_compute_subnetwork.webapp[count.index].self_link

    access_config {

    }

  }

  allow_stopping_for_update = var.compute_engine.compute_engine_allow_stopping_for_update

  service_account {
    email  = google_service_account.service_account.email
    scopes = var.compute_engine.compute_engine_service_account_scopes
  }

  tags       = [var.compute_engine.compute_engine_webapp_tag]
  depends_on = [google_compute_subnetwork.webapp, google_compute_firewall.allow_iap, google_compute_firewall.deny_all, google_sql_database.webapp_db, google_sql_user.webapp_db_user, google_project_iam_binding.service_account_logging_admin, google_project_iam_binding.service_account_monitoring_metric_writer, google_pubsub_topic.verify_email_topic, google_pubsub_subscription.verify_email_subscription, google_vpc_access_connector.serverless_connector]

  metadata_startup_script = "#!/bin/bash\nset -e\nsudo touch /opt/csye6225/webapp/.env\nsudo echo \"PORT=${var.env_port}\" > /opt/csye6225/webapp/.env\nsudo echo \"DATABASE_NAME=${var.database.database_name}\" >> /opt/csye6225/webapp/.env\nsudo echo \"DATABASE_USERNAME=${var.database.database_user}\" >> /opt/csye6225/webapp/.env\nsudo echo \"DATABASE_PASSWORD=${random_password.webapp_db_password.result}\" >> /opt/csye6225/webapp/.env\nsudo echo \"DATABASE_HOST=${google_sql_database_instance.webapp_cloudsql_instance.ip_address.0.ip_address}\" >> /opt/csye6225/webapp/.env\nsudo echo \"DATABASE_DIALECT=${var.env_db_dialect}\" >> /opt/csye6225/webapp/.env\nsudo echo \"DROP_DATABASE=${var.env_db_drop_db}\" >> /opt/csye6225/webapp/.env\nsudo echo \"TOPIC_VERIFY_EMAIL=${var.env_topic_verify_email}\" >> /opt/csye6225/webapp/.env\nsudo echo \"VERIFY_EMAIL_EXPIRY_MILLISECONDS=${var.env_verify_email_expiry_milliseconds}\" >> /opt/csye6225/webapp/.env\nsudo systemctl daemon-reload\nsudo systemctl restart webapp\nsudo systemctl daemon-reload\n"

}

resource "google_sql_database_instance" "webapp_cloudsql_instance" {
  name                = var.database.name
  database_version    = var.database.database_version
  region              = var.database.region
  deletion_protection = var.database.deletion_protection
  root_password       = var.database.root_password

  settings {
    tier              = var.database.tier
    availability_type = var.database.availability_type
    disk_type         = var.database.disk_type
    disk_size         = var.database.disk_size

    dynamic "ip_configuration" {
      for_each = google_compute_network.vpc
      iterator = vpc
      content {
        ipv4_enabled                                  = var.database.ipv4_enabled
        private_network                               = vpc.value.self_link
        enable_private_path_for_google_cloud_services = var.database.enabled_private_path
      }
    }

  }

  depends_on = [google_compute_network.vpc, google_service_networking_connection.private_vpc_connection, google_pubsub_subscription.verify_email_subscription, google_pubsub_topic_iam_binding.verify_email_topic_binding]
}

resource "google_sql_database" "webapp_db" {
  name     = var.database.database_name
  instance = google_sql_database_instance.webapp_cloudsql_instance.name

  depends_on = [google_sql_database_instance.webapp_cloudsql_instance]
}

resource "random_password" "webapp_db_password" {
  length           = var.database.password_length
  special          = var.database.password_includes_special
  override_special = var.database.password_override_special
}

resource "google_sql_user" "webapp_db_user" {
  name     = var.database.database_user
  instance = google_sql_database_instance.webapp_cloudsql_instance.name
  password = random_password.webapp_db_password.result

  depends_on = [google_sql_database_instance.webapp_cloudsql_instance, random_password.webapp_db_password]
}

resource "google_pubsub_schema" "verify_email_schema" {
  name       = var.pubsub_verify_email.schema.name
  type       = var.pubsub_verify_email.schema.type
  definition = var.pubsub_verify_email.schema.definition
}

resource "google_pubsub_topic" "verify_email_topic" {
  project                    = var.project_id
  name                       = var.pubsub_verify_email.topic.name
  message_retention_duration = var.pubsub_verify_email.topic.message_retention_duration

  schema_settings {
    schema   = "projects/${var.project_id}/schemas/${google_pubsub_schema.verify_email_schema.name}"
    encoding = var.pubsub_verify_email.topic.schema_settings_encoding
  }

  depends_on = [google_pubsub_schema.verify_email_schema]
}

resource "google_pubsub_subscription" "verify_email_subscription" {
  name  = var.pubsub_verify_email.subscription.name
  topic = google_pubsub_topic.verify_email_topic.name

  depends_on = [google_pubsub_topic.verify_email_topic]
}

resource "google_cloudfunctions2_function" "function" {
  count       = var.replica
  project     = var.project_id
  name        = "${var.cloud_function.name}-${count.index}"
  location    = var.region
  description = var.cloud_function.description

  build_config {
    runtime     = var.cloud_function.build_config.runtime
    entry_point = var.cloud_function.build_config.entry_point
    environment_variables = {
      BUILD_CONFIG_TEST = "build_test"
    }
    source {
      storage_source {
        bucket = var.cloud_function.build_config.source_bucket
        object = var.cloud_function.build_config.source_object
      }
    }
  }

  service_config {
    timeout_seconds = var.cloud_function.service_config.timeout_seconds
    environment_variables = {
      MAILGUN_API_KEY   = var.cloud_function.service_config.environment_variables.MAILGUN_API_KEY
      MAILGUN_DOMAIN_NAME    = var.cloud_function.service_config.environment_variables.MAILGUN_DOMAIN
      MAILGUN_FROM_ADDRESS      = var.cloud_function.service_config.environment_variables.MAILGUN_FROM
      VERIFICATION_EMAIL_LINK = var.cloud_function.service_config.environment_variables.VERIFY_EMAIL_LINK
      DATABASE_NAME     = var.database.database_name
      DATABASE_USERNAME     = var.database.database_user
      DATABASE_PASSWORD = random_password.webapp_db_password.result
      DATABASE_HOST     = google_sql_database_instance.webapp_cloudsql_instance.ip_address.0.ip_address
    }
    available_memory                 = var.cloud_function.service_config.available_memory
    max_instance_request_concurrency = var.cloud_function.service_config.max_instance_request_concurrency
    min_instance_count               = var.cloud_function.service_config.min_instance_count
    max_instance_count               = var.cloud_function.service_config.max_instance_count
    available_cpu                    = var.cloud_function.service_config.available_cpu
    ingress_settings                 = var.cloud_function.service_config.ingress_settings

    vpc_connector = google_vpc_access_connector.serverless_connector[count.index].name

    vpc_connector_egress_settings  = var.cloud_function.service_config.vpc_connector_egress_settings
    service_account_email          = google_service_account.service_account.email
    all_traffic_on_latest_revision = var.cloud_function.service_config.all_traffic_on_latest_revision
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = var.cloud_function.event_trigger.event_type
    pubsub_topic          = "projects/${var.project_id}/topics/${google_pubsub_topic.verify_email_topic.name}"
    retry_policy          = var.cloud_function.event_trigger.retry_policy
    service_account_email = google_service_account.service_account.email
  }

  depends_on = [google_sql_database_instance.webapp_cloudsql_instance, google_pubsub_topic.verify_email_topic, google_compute_instance.webapp_instance]
}

resource "google_cloud_run_service_iam_member" "cloud_run_invoker" {
  count    = var.replica
  project  = google_cloudfunctions2_function.function[count.index].project
  location = google_cloudfunctions2_function.function[count.index].location
  service  = google_cloudfunctions2_function.function[count.index].name
  role     = var.roles.cloud_run_invoker_role
  member   = "serviceAccount:${google_service_account.service_account.email}"

  depends_on = [google_cloudfunctions2_function.function, google_service_account.service_account]
}



variable "service_account_file_path" {
  description = "The path to the service account key file."
  type        = string
}

variable "project_id" {
  description = "The ID of the Google Cloud Platform project."
  type        = string
}

variable "region" {
  description = "The region to deploy the resources."
  type        = string
}

variable "replica" {
  description = "The number of replicas to deploy."
  type        = number
}

variable "vpc_subnet_webapp" {
  description = "values for webapp subnet"
  type = object({
    name          = string
    ip_cidr_range = string

  })
}

variable "vpc_subnet_db" {
  description = "values for db subnet"
  type = object({
    name                            = string
    ip_cidr_range                   = string
    enable_private_ip_google_access = bool
  })
}

variable "vpc" {
  description = "values for vpc"
  type = object({
    name                    = string
    auto_create_subnetworks = bool
    delete_default_routes   = bool
    routing_mode            = string
  })

}

variable "vpc_webapp_route" {
  description = "values for webapp route"
  type = object({
    name             = string
    dest_range       = string
    next_hop_gateway = string

  })

}

variable "private_ip_address" {
  description = "values for private ip address"
  type = object({
    name                         = string
    global_address_address_type  = string
    global_address_purpose       = string
    global_address_prefix_length = number
  })
}

variable "private_vpc_connection" {
  description = "values for private vpc connection"
  type = object({
    google_service_nw_connection_service = string
  })
}

variable "serverless_vpc_access" {
  description = "values for serverless vpc access"
  type = object({
    name               = string
    ip_cidr_range      = string
    machine_type       = string
    minimum_instances  = number
    maximum_instances  = number
    maximum_throughput = number
  })
}

variable "firewall_allow" {
  description = "values for firewall allow"
  type = object({
    firewall_allow_protocol = string
    firewall_allow_ports    = list(string)
    firewall_allow_priority = number
  })
}

variable "firewall_deny" {
  description = "values for firewall allow"
  type = object({
    firewall_deny_priority = number
  })
}


variable "compute_engine" {
  description = "values for compute engine"
  type = object({
    compute_engine_webapp_tag                = string
    compute_engine_machine_type              = string
    compute_engine_machine_zone              = string
    boot_disk_image                          = string
    boot_disk_type                           = string
    boot_disk_size                           = number
    compute_engine_allow_stopping_for_update = bool
    compute_engine_service_account_scopes    = list(string)
  })
}

variable "dns_record" {
  description = "values for dns record"
  type = object({
    domain_name           = string
    managed_zone_dns_name = string
    ttl                   = number
    type                  = string
  })
}

variable "database" {
  description = "values for database"
  type = object({
    name                      = string
    database_version          = string
    region                    = string
    deletion_protection       = bool
    tier                      = string
    availability_type         = string
    disk_type                 = string
    disk_size                 = number
    ipv4_enabled              = bool
    enabled_private_path      = bool
    database_name             = string
    password_length           = number
    password_includes_special = bool
    password_override_special = string
    database_user             = string
    root_password             = string
  })
}

variable "service_account" {
  description = "Service account variables"
  type = object({
    account_id                   = string
    display_name                 = string
    create_ignore_already_exists = bool
  })

}

variable "roles" {
  description = "Project Iam Binding Roles"
  type = object({
    logging_admin_role            = string
    monitoring_metric_writer_role = string

    pubsub_publisher_role              = string
    service_account_token_creator_role = string

    cloud_functions_developer_role = string
    cloud_run_invoker_role         = string

    artifact_registry_create_on_push_writer = string
    storage_object_admin_role               = string
    logs_writer_role                        = string
  })
}

variable "pubsub_verify_email" {
  description = "PubSub verify email variables"
  type = object({
    schema = object({
      name       = string
      type       = string
      definition = string
    })
    topic = object({
      name                       = string
      message_retention_duration = string
      schema_settings_encoding   = string
    })
    subscription = object({
      name = string
    })
  })
}

variable "cloud_function" {
  description = "Cloud Function variables"
  type = object({
    name        = string
    description = string

    build_config = object({
      entry_point   = string
      runtime       = string
      source_bucket = string
      source_object = string
    })

    service_config = object({
      environment_variables = object({
        MAILGUN_API_KEY   = string
        MAILGUN_DOMAIN    = string
        MAILGUN_FROM      = string
        VERIFY_EMAIL_LINK = string
      })
      timeout_seconds                  = number
      available_memory                 = string
      max_instance_request_concurrency = number
      min_instance_count               = number
      max_instance_count               = number
      available_cpu                    = number
      ingress_settings                 = string
      vpc_connector_egress_settings    = string
      all_traffic_on_latest_revision   = bool
    })

    event_trigger = object({
      event_type   = string
      resource     = string
      retry_policy = string
    })
  })
}

variable "env_port" {
  description = "The port to run the application on."
  type        = string
}

variable "env_db_dialect" {
  description = "The database dialect to use."
  type        = string
}

variable "env_db_drop_db" {
  description = "Whether to drop the database on startup."
  type        = bool
}

variable "env_topic_verify_email" {
  description = "The name of the Pub/Sub topic to verify email addresses."
  type        = string
}

variable "env_verify_email_expiry_milliseconds" {
  description = "The expiry time for the email verification link in milliseconds."
  type        = number
}




