resource "google_project_service" "iam_api" {
  service = "iam.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }
  disable_on_destroy = false
}

resource "google_project_service" "cloud_run_api" {
  service = "run.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }
  disable_on_destroy = false
}

resource "google_service_account" "sgtm_service_account" {
  project      = var.project_id
  account_id   = local.run_service_account_id
  display_name = "Service account for sGTM"

  depends_on = [google_project_service.iam_api]
}

resource "google_project_iam_member" "sgtm_service_account_logging" {
  project    = var.project_id
  role       = "roles/logging.logWriter"
  member     = "serviceAccount:${google_service_account.sgtm_service_account.email}"
  depends_on = [google_service_account.sgtm_service_account]
}

resource "google_cloud_run_v2_service" "sgtm-cr" {
  depends_on = [
    google_project_service.cloud_run_api,
    google_project_iam_member.sgtm_service_account_logging,
  ]
  for_each   = toset(var.regions)
  location   = each.key
  name       = "${var.resource_prefix}-gcr-sgtm-${each.key}"
  ingress    = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.sgtm_service_account.email
    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }
    containers {
      name  = "gtm-cloud-image-1"
      image = var.container_image
      env {
        name  = "CONTAINER_CONFIG"
        value = var.container_config
      }
      env {
        name  = "PREVIEW_SERVER_URL"
        value = var.deploy_preview_server ? google_cloud_run_v2_service.sgtm-cr-preview[0].uri : ""
      }
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
    }
  }
}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  for_each = toset(var.regions)
  location = each.key
  service  = google_cloud_run_v2_service.sgtm-cr[each.key].name

  policy_data = data.google_iam_policy.noauth.policy_data
}

resource "google_cloud_run_v2_service" "sgtm-cr-preview" {
  count      = var.deploy_preview_server ? 1 : 0
  depends_on = [
    google_project_service.cloud_run_api,
    google_project_iam_member.sgtm_service_account_logging,
  ]
  location   = var.preview_region
  name       = "${var.resource_prefix}-sgtm-preview-server"
  ingress    = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.sgtm_service_account.email
    scaling {
      min_instance_count = var.min_preview_instance_count
      max_instance_count = var.max_preview_instance_count
    }
    containers {
      image = var.container_image
      env {
        name  = "CONTAINER_CONFIG"
        value = var.container_config
      }
      env {
        name  = "RUN_AS_PREVIEW_SERVER"
        value = "true"
      }
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
    }
  }
}

resource "google_cloud_run_service_iam_policy" "noauth_preview" {
  count    = var.deploy_preview_server ? 1 : 0
  location = var.preview_region
  service  = google_cloud_run_v2_service.sgtm-cr-preview[0].name

  policy_data = data.google_iam_policy.noauth.policy_data
}
