# README

This repository contains Notebook files for Task 2, 3 of the DN Pursuit DA Hackathon

## Terraform Configuration Updates

This section summarizes the recent changes made to the Terraform configuration to set up the Qwiklab environment. These changes were made to address several issues encountered during deployment and to align the configuration with organizational policies.

### `main.tf`

*   **Resource Cleanup:**
    *   The **Model Armor** and **Cloud Run** services were removed from the configuration as they are not needed for this lab. The corresponding API activations (`run.googleapis.com`, `modelarmor.googleapis.com`, `artifactregistry.googleapis.com`, `cloudbuild.googleapis.com`) were also removed to keep the project clean.

*   **Networking:**
    *   A new **VPC network** (`qwiklab-vpc`) is now created to provide a dedicated network for the lab resources, rather than relying on the default network.
    *   The **Compute Engine VM** is now configured to use this new VPC.
    *   The VM is no longer assigned a public IP address to comply with an organizational policy (`constraints/compute.vmExternalIpAccess`) that restricts external IP access.

*   **Google Cloud Storage:**
    *   The GCS bucket now enforces **uniform bucket-level access**. This is a security best practice and was required by an organizational policy (`constraints/storage.uniformBucketLevelAccess`).
    *   The resource attempting to set public access at the object level was commented out to comply with the uniform access policy.

*   **BigQuery:**
    *   A **default 30-day table expiration** has been added to the BigQuery dataset. This was necessary to resolve an issue where the project's billing status was not being detected by the BigQuery API.
    *   The dataset is now configured to **delete its contents on destroy**, which is convenient for lab environments.
    *   The data loading for the `products` table has been fixed. It now correctly loads data from `products_info.csv` instead of a non-existent `products.json` file. The load job has been updated to handle the CSV format and skip the header row.

*   **Compute Engine Security:**
    *   The VM is now configured as a **Shielded VM** with **Secure Boot enabled**. This was required by an organizational policy (`constraints/compute.requireShieldedVm`) and enhances the security of the VM.

### `output.tf`

*   The output for the Cloud Run service URL (`model_armor_demo_url`) was removed, as the service is no longer part of the configuration.