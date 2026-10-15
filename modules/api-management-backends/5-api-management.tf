# ---------------------------------------------------------------------------
# API Management - the one front door for the three apps.
#
# Callers send every request to the gateway with a subscription key. The
# gateway picks the API by the first path segment (/catalog, /orders or
# /reviews), checks the key and the product's rate limit, then hands the
# request to that API's backend, which adds the app's credential and
# forwards it.
# ---------------------------------------------------------------------------
resource "azurerm_api_management" "main" {
  name                = "${var.name_prefix}-apim"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = "Developer_1"
  tags                = var.tags
}

locals {
  # One API, backend and named value per app. url is where the backend sends
  # requests, resource_id links the backend to its app (as Azure's "import
  # from Function App / App Service" does), and header is the credential the
  # app checks. The credentials themselves are in secrets below: a sensitive
  # value can't be part of a for_each map.
  apis = {
    catalog = {
      display_name = "Catalog"
      description  = "The catalog Function App."
      url          = "https://${azurerm_linux_function_app.main["catalog"].default_hostname}/api"
      resource_id  = "https://management.azure.com${azurerm_linux_function_app.main["catalog"].id}"
      header       = "x-functions-key"
      named_value  = "catalog-function-key"
    }
    orders = {
      display_name = "Orders"
      description  = "The orders Function App."
      url          = "https://${azurerm_linux_function_app.main["orders"].default_hostname}/api"
      resource_id  = "https://management.azure.com${azurerm_linux_function_app.main["orders"].id}"
      header       = "x-functions-key"
      named_value  = "orders-function-key"
    }
    reviews = {
      display_name = "Reviews"
      description  = "The reviews Web App."
      url          = "https://${azurerm_linux_web_app.reviews.default_hostname}"
      resource_id  = "https://management.azure.com${azurerm_linux_web_app.reviews.id}"
      header       = "x-api-key"
      named_value  = "reviews-api-key"
    }
  }
}

locals {
  secrets = {
    catalog = data.azurerm_function_app_host_keys.main["catalog"].default_function_key
    orders  = data.azurerm_function_app_host_keys.main["orders"].default_function_key
    reviews = random_password.reviews_api_key.result
  }
}

# ---------------------------------------------------------------------------
# Named values - each app's credential, stored as a secret so it isn't shown
# in the portal or returned by a plain GET. The backends refer to them as
# {{<name>}}, and the gateway substitutes the value per request.
# ---------------------------------------------------------------------------
resource "azurerm_api_management_named_value" "main" {
  for_each = local.apis

  name                = each.value.named_value
  display_name        = each.value.named_value
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  value               = local.secrets[each.key]
  secret              = true
}

# ---------------------------------------------------------------------------
# Backends - one per app. Each holds the app's URL and the credential header
# the gateway adds to every request it forwards there, so no policy has to
# set it and callers never see it.
# ---------------------------------------------------------------------------
resource "azurerm_api_management_backend" "main" {
  for_each = local.apis

  name                = each.key
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  protocol            = "http"
  url                 = each.value.url
  resource_id         = each.value.resource_id
  description         = each.value.description

  credentials {
    header = {
      (each.value.header) = "{{${azurerm_api_management_named_value.main[each.key].display_name}}}"
    }
  }
}

# ---------------------------------------------------------------------------
# One API per app. None has a service_url: the API's policy picks its
# backend, and the backend supplies the URL. The gateway strips the API's
# path and appends the rest to the backend's URL, so
#   GET  <gateway>/catalog/products/mug  ->  <catalog app>/api/products/mug
#   POST <gateway>/orders/orders         ->  <orders app>/api/orders
#   GET  <gateway>/reviews/reviews       ->  <reviews app>/reviews
# ---------------------------------------------------------------------------
resource "azurerm_api_management_api" "main" {
  for_each = local.apis

  name                  = each.key
  display_name          = each.value.display_name
  path                  = each.key
  protocols             = ["https"]
  revision              = "1"
  subscription_required = true
  resource_group_name   = azurerm_resource_group.main.name
  api_management_name   = azurerm_api_management.main.name
}

# ---------------------------------------------------------------------------
# Operations - the gateway routes only requests that match one of an API's
# operations, so each route is declared here with its method and template.
# Anything else gets a 404 from the gateway without reaching the app.
# ---------------------------------------------------------------------------
locals {
  operations = {
    "catalog-list-products" = { api = "catalog", method = "GET", url_template = "/products", display_name = "List products" }
    "catalog-get-product"   = { api = "catalog", method = "GET", url_template = "/products/{id}", display_name = "Get a product", params = ["id"] }
    "orders-list-orders"    = { api = "orders", method = "GET", url_template = "/orders", display_name = "List orders" }
    "orders-place-order"    = { api = "orders", method = "POST", url_template = "/orders", display_name = "Place an order" }
    "reviews-list-reviews"  = { api = "reviews", method = "GET", url_template = "/reviews", display_name = "List reviews" }
    "reviews-add-review"    = { api = "reviews", method = "POST", url_template = "/reviews", display_name = "Add a review" }
  }
}

resource "azurerm_api_management_api_operation" "main" {
  for_each = local.operations

  operation_id        = each.key
  api_name            = azurerm_api_management_api.main[each.value.api].name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = each.value.display_name
  method              = each.value.method
  url_template        = each.value.url_template

  dynamic "template_parameter" {
    for_each = lookup(each.value, "params", [])
    content {
      name     = template_parameter.value
      type     = "string"
      required = true
    }
  }
}

# ---------------------------------------------------------------------------
# API policies - send each request to the API's backend, and mark it as
# having come through the gateway (the apps echo this back as "via", so you
# can see the path a request took).
# ---------------------------------------------------------------------------
resource "azurerm_api_management_api_policy" "main" {
  for_each = local.apis

  api_name            = azurerm_api_management_api.main[each.key].name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = <<-XML
    <policies>
      <inbound>
        <base />
        <set-backend-service backend-id="${azurerm_api_management_backend.main[each.key].name}" />
        <set-header name="x-forwarded-by" exists-action="override">
          <value>${azurerm_api_management.main.name}</value>
        </set-header>
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML
}

# ---------------------------------------------------------------------------
# Product - groups the three APIs into one offering that a subscription
# grants access to, and applies a rate limit to every subscription to it.
# ---------------------------------------------------------------------------
resource "azurerm_api_management_product" "shop" {
  product_id            = "shop"
  display_name          = "Shop"
  description           = "The catalog, orders and reviews APIs."
  api_management_name   = azurerm_api_management.main.name
  resource_group_name   = azurerm_resource_group.main.name
  subscription_required = true
  approval_required     = false
  published             = true
}

resource "azurerm_api_management_product_api" "shop" {
  for_each = local.apis

  api_name            = azurerm_api_management_api.main[each.key].name
  product_id          = azurerm_api_management_product.shop.product_id
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
}

# The limit is counted per subscription: each key gets its own allowance, and
# a key that goes over it gets a 429 with a Retry-After header.
resource "azurerm_api_management_product_policy" "shop" {
  product_id          = azurerm_api_management_product.shop.product_id
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = <<-XML
    <policies>
      <inbound>
        <base />
        <rate-limit calls="${var.rate_limit_calls}" renewal-period="${var.rate_limit_period}" />
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
  XML
}

# ---------------------------------------------------------------------------
# Subscription - the key callers send in the Ocp-Apim-Subscription-Key
# header. It's scoped to the Shop product, so it opens all three APIs and is
# subject to the product's rate limit.
# ---------------------------------------------------------------------------
resource "azurerm_api_management_subscription" "shop" {
  display_name        = "Shop example"
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  product_id          = azurerm_api_management_product.shop.id
  state               = "active"
}
