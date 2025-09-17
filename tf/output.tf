output "gcs_bucket_name" {
  value       = google_storage_bucket.cloud-bucket.name
  description = "Name of the GCS Bucket"
}

output "model_armor_demo_url" {
  value       = google_cloud_run_v2_service.model_armor_demo.uri
}