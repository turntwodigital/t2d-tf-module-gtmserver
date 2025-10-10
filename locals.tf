locals {
  run_service_account_id   = coalesce(var.run_service_account_id, "${var.resource_prefix}-sgtm-run-sa")
  build_service_account_id = coalesce(var.build_service_account_id, "${var.resource_prefix}-sgtm-build-sa")
  auto_update_location     = var.regions[0]
}
