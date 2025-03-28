resource "google_project_service" "cloud_run_api" {
  service = "run.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }
  disable_on_destroy = false
}

resource "google_cloud_run_v2_service" "sgtm-cr" {
  depends_on = [google_project_service.cloud_run_api]
  for_each   = toset(var.regions)
  location   = each.key
  name       = "${var.resource_prefix}-gcr-sgtm-${each.key}"
  ingress    = "INGRESS_TRAFFIC_ALL"

  template {
    scaling {
      min_instance_count = var.min_instance_count
      max_instance_count = var.max_instance_count
    }
    containers {
      name  = "gtm-cloud-image-1"
      image = "gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable"
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
  depends_on = [google_project_service.cloud_run_api]
  location   = var.preview_region
  name       = "${var.resource_prefix}-gcr-sgtm-preview-server"
  ingress    = "INGRESS_TRAFFIC_ALL"

  template {
    scaling {
      min_instance_count = 1
      max_instance_count = 1
    }
    containers {
      image = "gcr.io/cloud-tagging-10302018/gtm-cloud-image:stable"
      env {
        name  = "CONTAINER_CONFIG"
        value = var.container_config
      }
      env {
        name  = "RUN_AS_PREVIEW_SERVER"
        value = true
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
