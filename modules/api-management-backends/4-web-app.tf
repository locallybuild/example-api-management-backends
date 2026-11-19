# ---------------------------------------------------------------------------
# The reviews Web App - a dependency-free Node app, zipped from app/reviews.
#
# It refuses any request without the x-api-key that API Management adds, so
# the gateway is the only way in. The key is generated here and given to both
# the app (as the API_KEY app setting) and API Management (as a secret named
# value its backend refers to, see 5-api-management.tf).
#
# It runs on the same App Service plan as the two Function Apps.
# ---------------------------------------------------------------------------
resource "random_password" "reviews_api_key" {
  length  = 32
  special = false
}

# The archive's name carries a hash of the app's directory (see locals.tf), so
# a code change produces a new zip_deploy_file and a redeploy.
data "archive_file" "reviews" {
  type        = "zip"
  source_dir  = local.reviews_dir
  output_path = "${path.module}/../../.build/reviews-${local.reviews_hash}.zip"
}

resource "azurerm_linux_web_app" "reviews" {
  name                = "${var.name_prefix}-reviews"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true
  tags                = var.tags

  zip_deploy_file = data.archive_file.reviews.output_path

  site_config {
    application_stack {
      node_version = "26"
    }
  }

  app_settings = {
    # The zip is the app as it runs; there's nothing to build.
    SCM_DO_BUILD_DURING_DEPLOYMENT = "false"

    API_KEY = random_password.reviews_api_key.result
  }
}
