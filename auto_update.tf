# Enable required services
resource "google_project_service" "cloud_build_api" {
  count   = var.enable_auto_updates ? 1 : 0
  project = var.project_id
  service = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloud_scheduler_api" {
  count   = var.enable_auto_updates ? 1 : 0
  project = var.project_id
  service = "cloudscheduler.googleapis.com"
  disable_on_destroy = false
}

# Cloud Build service account
resource "google_service_account" "cloud_builder" {
  count        = var.enable_auto_updates ? 1 : 0
  project      = var.project_id
  account_id   = local.build_service_account_id
  display_name = "Service account for Cloud Build"
  depends_on   = [google_project_service.cloud_build_api]
}

# IAM bindings for Cloud Build permissions
resource "google_project_iam_custom_role" "cloud_builder" {
  count       = var.enable_auto_updates ? 1 : 0
  project     = var.project_id
  role_id     = format("%s_runner", replace(lower(local.build_service_account_id), "-", ""))
  title       = "Cloud Build Runner"
  description = "Permissions to trigger Cloud Builds for sGTM"
  permissions = [
    "cloudbuild.builds.create",
    "cloudscheduler.jobs.run",
    "logging.logEntries.create",
    "logging.logEntries.route",
  ]
  depends_on = [google_project_service.cloud_build_api]
}

resource "google_project_iam_member" "cloud_builder_custom" {
  count   = var.enable_auto_updates ? 1 : 0
  project = var.project_id
  role    = google_project_iam_custom_role.cloud_builder[0].name
  member  = "serviceAccount:${google_service_account.cloud_builder[0].email}"
}

resource "google_project_iam_member" "cloud_builder_run_admin" {
  count   = var.enable_auto_updates ? 1 : 0
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cloud_builder[0].email}"
}

resource "google_project_iam_member" "cloud_builder_sa_user" {
  count   = var.enable_auto_updates ? 1 : 0
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloud_builder[0].email}"
}

# ---------- Key change starts here ----------

# Define the build configuration (like inline trigger)
locals {
  sgtm_build = jsonencode({
    steps = concat([
      for region in var.regions : {
        name       = "gcr.io/google.com/cloudsdktool/cloud-sdk"
        entrypoint = "gcloud"
        args = [
          "run", "deploy",
          google_cloud_run_v2_service.sgtm-cr[region].name,
          "--service-account", google_service_account.sgtm_service_account.email,
          "--region", region,
          "--image", var.container_image,
          "--min-instances", tostring(var.min_instance_count),
          "--max-instances", tostring(var.max_instance_count),
          "--allow-unauthenticated",
          "--no-cpu-throttling",
          "--update-env-vars",
          "PREVIEW_SERVER_URL=${try(google_cloud_run_v2_service.sgtm-cr-preview[0].uri, "")},CONTAINER_CONFIG=${var.container_config},GOOGLE_CLOUD_PROJECT=${var.project_id}",
        ]
      }
    ],
    var.deploy_preview_server ? [
      {
        name       = "gcr.io/google.com/cloudsdktool/cloud-sdk",
        entrypoint = "gcloud",
        args = [
          "run", "deploy",
          google_cloud_run_v2_service.sgtm-cr-preview[0].name,
          "--service-account", google_service_account.sgtm_service_account.email,
          "--region", var.preview_region,
          "--image", var.container_image,
          "--min-instances", tostring(var.min_preview_instance_count),
          "--max-instances", tostring(var.max_preview_instance_count),
          "--allow-unauthenticated",
          "--no-cpu-throttling",
          "--update-env-vars",
          "RUN_AS_PREVIEW_SERVER=true,CONTAINER_CONFIG=${var.container_config},GOOGLE_CLOUD_PROJECT=${var.project_id}",
        ]
      }
    ] : []),
    options = {
      logging = "CLOUD_LOGGING_ONLY"
    }
  })
}

# Scheduler calls Cloud Build directly using the inline build definition
resource "google_cloud_scheduler_job" "sgtm_update" {
  count = var.enable_auto_updates && length(var.cron_schedule) > 0 ? 1 : 0

  project     = var.project_id
  region      = local.auto_update_location
  name        = "${var.resource_prefix}-sgtm-update"
  description = "Trigger Cloud Build to update sGTM"

  schedule  = var.cron_schedule
  time_zone = var.cron_timezone

  http_target {
    http_method = "POST"
    uri         = "https://cloudbuild.googleapis.com/v1/projects/${var.project_id}/builds"
    body        = local.sgtm_build

    oauth_token {
      service_account_email = google_service_account.cloud_builder[0].email
    }

    headers = {
      "Content-Type" = "application/json"
    }
  }

  depends_on = [
    google_cloud_run_v2_service.sgtm-cr,
    google_project_service.cloud_build_api,
    google_project_service.cloud_scheduler_api,
  ]
}
