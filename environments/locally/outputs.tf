output "gateway_url" {
  description = "The API Management gateway's base URL."
  value       = module.api-management-backends.gateway_url
}

output "products_url" {
  description = "Lists the products, through the gateway (GET). Append /<id> for one product."
  value       = module.api-management-backends.products_url
}

output "orders_url" {
  description = "Lists (GET) and places (POST) orders, through the gateway."
  value       = module.api-management-backends.orders_url
}

output "reviews_url" {
  description = "Lists (GET, optionally ?productId=) and adds (POST) reviews, through the gateway."
  value       = module.api-management-backends.reviews_url
}

output "subscription_key" {
  description = "The Shop subscription's primary key, sent as the Ocp-Apim-Subscription-Key header."
  value       = module.api-management-backends.subscription_key
  sensitive   = true
}

output "app_urls" {
  description = "Each app's own URL, which refuses calls that don't carry the app's credential."
  value       = module.api-management-backends.app_urls
}

output "api_management_name" {
  description = "The name of the API Management instance."
  value       = module.api-management-backends.api_management_name
}
