resource "google_cloudbuild_trigger" "sgtm_update" {
  count           = var.enable_auto_updates ? 1 : 0
  name            = "${var.resource_prefix}-sgtm-update"
  description     = "Creates new revisions in Cloud Run for sGTM"
  location        = local.auto_update_location
  service_account = google_service_account.cloud_builder[0].id

  # FIX: Add webhook_config to satisfy required argument
  webhook_config {
    secret = "" # Optionally use a Secret Manager secret instead of empty string
  }

  build {
    dynamic "step" {
      for_each = var.regions
      content {
        name       = "gcr.io/google.com/cloudsdktool/cloud-sdk"
        entrypoint = "gcloud"
        args = [
          "run",
          "deploy",
          google_cloud_run_v2_service.sgtm-cr[step.value].name,
          "--service-account",
          google_service_account.sgtm_service_account.email,
          "--region",
          step.value,
          "--image",
          var.container_image,
          "--min-instances",
          tostring(var.min_instance_count),
          "--max-instances",
          tostring(var.max_instance_count),
          "--allow-unauthenticated",
          "--no-cpu-throttling",
          "--update-env-vars",
          "PREVIEW_SERVER_URL=${try(google_cloud_run_v2_service.sgtm-cr-preview[0].uri, "")},CONTAINER_CONFIG=${var.container_config},GOOGLE_CLOUD_PROJECT=${var.project_id}",
        ]
      }
    }

    dynamic "step" {
      for_each = var.deploy_preview_server ? [google_cloud_run_v2_service.sgtm-cr-preview[0].name] : []
      content {
        name       = "gcr.io/google.com/cloudsdktool/cloud-sdk"
        entrypoint = "gcloud"
        args = [
          "run",
          "deploy",
          step.value,
          "--service-account",
          google_service_account.sgtm_service_account.email,
          "--region",
          var.preview_region,
          "--image",
          var.container_image,
          "--min-instances",
          tostring(var.min_preview_instance_count),
          "--max-instances",
          tostring(var.max_preview_instance_count),
          "--allow-unauthenticated",
          "--no-cpu-throttling",
          "--update-env-vars",
          "RUN_AS_PREVIEW_SERVER=true,CONTAINER_CONFIG=${var.container_config},GOOGLE_CLOUD_PROJECT=${var.project_id}",
        ]
      }
    }

    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
  }

  approval_config {
    approval_required = false
  }

  depends_on = [
    google_cloud_run_v2_service.sgtm-cr,
    google_project_iam_member.cloud_builder_sa_user,
    google_project_service.cloud_build_api[0],
  ]
}
