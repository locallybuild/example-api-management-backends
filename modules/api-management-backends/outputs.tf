output "gateway_url" {
  description = "The API Management gateway's base URL."
  value       = azurerm_api_management.main.gateway_url
}

output "products_url" {
  description = "Lists the products, through the gateway (GET). Append /<id> for one product."
  value       = "${azurerm_api_management.main.gateway_url}/${azurerm_api_management_api.main["catalog"].path}/products"
}

output "orders_url" {
  description = "Lists (GET) and places (POST) orders, through the gateway."
  value       = "${azurerm_api_management.main.gateway_url}/${azurerm_api_management_api.main["orders"].path}/orders"
}

output "reviews_url" {
  description = "Lists (GET, optionally ?productId=) and adds (POST) reviews, through the gateway."
  value       = "${azurerm_api_management.main.gateway_url}/${azurerm_api_management_api.main["reviews"].path}/reviews"
}

output "subscription_key" {
  description = "The Shop subscription's primary key, sent as the Ocp-Apim-Subscription-Key header."
  value       = azurerm_api_management_subscription.shop.primary_key
  sensitive   = true
}

output "app_urls" {
  description = "Each app's own URL, which refuses calls that don't carry the app's credential."
  value = {
    catalog = "https://${azurerm_linux_function_app.main["catalog"].default_hostname}/api"
    orders  = "https://${azurerm_linux_function_app.main["orders"].default_hostname}/api"
    reviews = "https://${azurerm_linux_web_app.reviews.default_hostname}"
  }
}

output "api_management_name" {
  description = "The name of the API Management instance."
  value       = azurerm_api_management.main.name
}

output "resource_group" {
  description = "The resource group containing the deployed resources."
  value       = azurerm_resource_group.main.name
}
