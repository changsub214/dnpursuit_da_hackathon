resource "google_project_service" "services" {
  for_each = toset([
    "compute.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com"
  ])
  project = var.gcp_project_id
  service = each.key
}

resource "google_compute_network" "vpc_network" {
  project                 = var.gcp_project_id
  name                    = "qwiklab-vpc"
  auto_create_subnetworks = true
}

resource "google_storage_bucket" "cloud-bucket" {
  name                        = "${var.gcp_project_id}-bucket"
  location                    = var.gcp_region
  project                     = var.gcp_project_id
  force_destroy               = true # Optional: Allows deletion of non-empty buckets during terraform destroy
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
}

# resource "google_storage_bucket_iam_member" "public_access" {
#   bucket = google_storage_bucket.cloud-bucket.name
#   role   = "roles/storage.objectViewer"
#   member = "allUsers"
# }

# ------------------------------------------------------------------------------
# Review GCS Upload
# ------------------------------------------------------------------------------
variable "local_review_directory" {
  description = "The path to the local 'review' directory."
  type        = string
  default     = "./review" # Assumes 'review' directory is in the same folder as main.tf
}

locals {
  review_files_to_upload = fileset(var.local_review_directory, "**/*")
}

resource "google_storage_bucket_object" "file_uploads" {
  for_each = local.review_files_to_upload

  bucket = google_storage_bucket.cloud-bucket.name
  name   = "review/${each.key}"
  source = "${var.local_review_directory}/${each.key}"

  # Optional: Automatically determine and set the MIME type for the object.
  #content_type = filemime("${var.local_upload_directory}/${each.key}")

  depends_on = [
    google_storage_bucket.cloud-bucket
  ]
}

# ------------------------------------------------------------------------------
# BigQuery
# ------------------------------------------------------------------------------
resource "google_bigquery_dataset" "dataset" {
  dataset_id                   = "cymbal"
  location                     = var.gcp_region
  delete_contents_on_destroy  = true
  default_table_expiration_ms = 2592000000
}

# ------------------------------------------------------------------------------
# BigQuery Table (Customers)
# ------------------------------------------------------------------------------
resource "google_bigquery_table" "customers_table" {
  project    = var.gcp_project_id
  dataset_id = google_bigquery_dataset.dataset.dataset_id
  table_id   = "customers"
  schema     = file("bq/alchemy_data1.json") # Path relative to the main.tf file

  depends_on = [
    google_bigquery_dataset.dataset
  ]
}

# ------------------------------------------------------------------------------
# BigQuery Table (Products)
# ------------------------------------------------------------------------------
resource "google_bigquery_table" "products_table" {
  project    = var.gcp_project_id
  dataset_id = google_bigquery_dataset.dataset.dataset_id
  table_id   = "products"
  schema     = file("bq/products_schema.json") # Path relative to the main.tf file

  depends_on = [
    google_bigquery_dataset.dataset
  ]
}

# ------------------------------------------------------------------------------
# Upload the alchemy_data1.csv file to GCS
# ------------------------------------------------------------------------------
resource "google_storage_bucket_object" "alchemy_csv_upload" {
  bucket = google_storage_bucket.cloud-bucket.name
  name   = "bq_data/alchemy_data1.csv" # Object name in GCS
  source = "bq/alchemy_data1.csv"      # Path to local CSV file, relative to main.tf

  depends_on = [
    google_storage_bucket.cloud-bucket
  ]
}

# ------------------------------------------------------------------------------
# Upload the products_info.csv file to GCS
# ------------------------------------------------------------------------------
resource "google_storage_bucket_object" "products_csv_upload" {
  bucket = google_storage_bucket.cloud-bucket.name
  name   = "bq_data/products_info.csv" # Object name in GCS
  source = "bq/products_info.csv"      # Path to local json file

  depends_on = [
    google_storage_bucket.cloud-bucket
  ]
}

# ------------------------------------------------------------------------------
# Upload the eventdata json to GCS
# ------------------------------------------------------------------------------
resource "google_storage_bucket_object" "eventdata_json_upload" {
  bucket = google_storage_bucket.cloud-bucket.name
  name   = "eventdata/recent_retail_events.json" # Object name in GCS
  source = "eventdata/recent_retail_events.json"      # Path to local json file

  depends_on = [
    google_storage_bucket.cloud-bucket
  ]
}
# ------------------------------------------------------------------------------
# Upload the eventdata py to GCS
# ------------------------------------------------------------------------------
resource "google_storage_bucket_object" "eventdata_py_upload" {
  bucket = google_storage_bucket.cloud-bucket.name
  name   = "eventdata/update_event_time.py" # Object name in GCS
  source = "eventdata/update_event_time.py"      # Path to local json file

  depends_on = [
    google_storage_bucket.cloud-bucket
  ]
}

# ------------------------------------------------------------------------------
# Compute to run startup script
# ------------------------------------------------------------------------------
resource "google_compute_instance" "lab_setup" {
  project      = var.gcp_project_id
  zone         = var.gcp_zone
  name         = "lab-setup"
  machine_type = "e2-standard-2"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  shielded_instance_config {
    enable_secure_boot = true
  }

  network_interface {
    network = google_compute_network.vpc_network.name
  }
  service_account {
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/devstorage.read_write"
    ]
  }

  metadata = {
    startup-script     = file("script/startup.sh")
  }
  depends_on = [google_storage_bucket_object.eventdata_json_upload, google_storage_bucket_object.eventdata_py_upload]
}

# ------------------------------------------------------------------------------
# BigQuery job to load data into the customers table
# ------------------------------------------------------------------------------
resource "google_bigquery_job" "load_customers_data" {
  project  = var.gcp_project_id
  location = var.gcp_region
  job_id   = "${var.gcp_project_id}-load-customers-data" # Unique job ID

  load {
    source_uris = [
      "gs://${google_storage_bucket.cloud-bucket.name}/${google_storage_bucket_object.alchemy_csv_upload.name}"
    ]

    destination_table {
      project_id = var.gcp_project_id
      dataset_id = google_bigquery_dataset.dataset.dataset_id
      table_id   = google_bigquery_table.customers_table.table_id
    }

    source_format      = "CSV"
    skip_leading_rows  = 1 # Skip the header row
    write_disposition  = "WRITE_TRUNCATE" # Overwrite table if it exists
    autodetect         = false # Rely on the table's predefined schema
  }

  depends_on = [
    google_storage_bucket_object.alchemy_csv_upload,
    google_bigquery_table.customers_table
  ]
}

# ------------------------------------------------------------------------------
# BigQuery job to load data into the products table
# ------------------------------------------------------------------------------
resource "google_bigquery_job" "load_products_data" {
  project  = var.gcp_project_id
  location = var.gcp_region
  job_id   = "${var.gcp_project_id}-load-products-data" # Unique job ID

  load {
    source_uris = [
      "gs://${google_storage_bucket.cloud-bucket.name}/${google_storage_bucket_object.products_csv_upload.name}"
    ]

    destination_table {
      project_id = var.gcp_project_id
      dataset_id = google_bigquery_dataset.dataset.dataset_id
      table_id   = google_bigquery_table.products_table.table_id
    }

    source_format      = "CSV"
    skip_leading_rows  = 1
    write_disposition  = "WRITE_TRUNCATE" # Overwrite table if it exists
    #autodetect         = false # Rely on the table's predefined schema
  }

  depends_on = [
    google_storage_bucket_object.products_csv_upload,
    google_bigquery_table.products_table
  ]
}