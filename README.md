# Example: Front Function Apps and a Web App with API Management backends within Locally

This example shows how to publish two Function Apps and a Web App through one Azure API Management instance on [Locally Build](https://locally.build), using API Management **backends** the way Azure's "import from Function App / App Service" sets them up. Callers use a single gateway with a single subscription key. Each API's policy picks its backend, and the backend adds the app's credential to every request it forwards. None of the apps accepts a call without that credential, so callers can't go around the gateway.

```
                                API Management (Developer)
                             ┌──────────────────────────────────────────────┐
 curl / browser ─────────▶   │  subscription key check (Shop product)       │
   Ocp-Apim-Subscription-Key │  rate-limit: 20 calls / 60s per key          │
                             │                                              │
                             │  /catalog/*  set-backend-service  catalog ───│──▶ catalog Function App
                             │                x-functions-key: {{catalog-…}}│      GET  /api/products[/{id}]
                             │  /orders/*   set-backend-service  orders  ───│──▶ orders Function App
                             │                x-functions-key: {{orders-…}} │      GET/POST /api/orders
                             │  /reviews/*  set-backend-service  reviews ───│──▶ reviews Web App
                             │                x-api-key: {{reviews-api-key}}│      GET/POST /reviews
                             └──────────────────────────────────────────────┘
```

The apps:

* **catalog** ([`functions/catalog`](./functions/catalog)) - a Function App. `GET /api/products` lists the products on sale, and `GET /api/products/{id}` returns one of them.
* **orders** ([`functions/orders`](./functions/orders)) - a Function App. `POST /api/orders` places an order (`{"productId": "mug", "quantity": 2}`), and `GET /api/orders` lists the orders placed so far.
* **reviews** ([`app/reviews`](./app/reviews)) - a Web App, in plain Node.js with no dependencies. `GET /reviews?productId=mug` lists a product's reviews, and `POST /reviews` adds one (`{"productId": "mug", "rating": 5, "text": "..."}`).

The functions use `authLevel: "function"`, so a request without a function key gets a `401` from the Function App itself. The Web App answers `401` to any request without the `x-api-key` it was configured with. Each response includes `via`, which says whether the request came through the gateway or went to the app directly.

### What API Management is configured with

| Resource | What it does |
| --- | --- |
| `azurerm_api_management` | The gateway itself, on the Developer SKU |
| `azurerm_api_management_named_value` (x3) | Each app's credential, stored as a **secret**: the two Function Apps' default function keys, and the Web App's API key |
| `azurerm_api_management_backend` (x3) | One per app: its `url`, its `resource_id` (the app's ARM ID, as Azure's import writes it), and `credentials` with the header the app checks, set to `{{<named value>}}` |
| `azurerm_api_management_api` (x3) | One API per app, at the paths `/catalog`, `/orders` and `/reviews`. None has a `service_url`: the backend supplies it |
| `azurerm_api_management_api_operation` (x6) | One per route. The gateway only routes requests that match an operation, and returns `404` for anything else without calling the app |
| `azurerm_api_management_api_policy` (x3) | `set-backend-service backend-id="<app>"`, plus an `x-forwarded-by` header |
| `azurerm_api_management_product` | **Shop**, which contains all three APIs and requires a subscription |
| `azurerm_api_management_product_policy` | `rate-limit`: 20 calls per 60 seconds for each subscription |
| `azurerm_api_management_subscription` | A key scoped to the Shop product, so one key opens all three APIs |

The gateway strips the API's path and appends the rest of the URL to the backend's `url`, so:

| Gateway request | Forwarded to |
| --- | --- |
| `GET  <gateway>/catalog/products/mug` | `GET  <catalog app>/api/products/mug` |
| `POST <gateway>/orders/orders` | `POST <orders app>/api/orders` |
| `GET  <gateway>/reviews/reviews?productId=mug` | `GET  <reviews app>/reviews?productId=mug` |

### Backend credentials

Each backend carries the header its app checks, with the value taken from a secret named value:

```hcl
resource "azurerm_api_management_backend" "main" {
  # ...
  url         = "https://<catalog app>/api"
  resource_id = "https://management.azure.com/subscriptions/.../sites/<catalog app>"

  credentials {
    header = {
      "x-functions-key" = "{{catalog-function-key}}"
    }
  }
}
```

and each API's policy only has to pick its backend:

```xml
<set-backend-service backend-id="catalog" />
```

The gateway fills in the named value for each request and replaces any value the caller sent under that header. As a result, the credential never appears in a policy, the callers never see it, and they only need their subscription key.

Terraform reads each Function App's default function key with the `azurerm_function_app_host_keys` data source. The Web App's key is generated with `random_password` and given to both the app (its `API_KEY` app setting) and API Management.

### Identity

The Function Apps connect to nothing except their host storage (`AzureWebJobsStorage`). Both run as a single **user-assigned managed identity** that holds `Storage Blob Data Owner` and `Storage Queue Data Contributor` on the Storage Account. Shared-key access is switched off on the account (`shared_access_key_enabled = false`). The Web App doesn't use storage. All three apps share one App Service plan.

## Requirements

* [Locally Build](https://locally.build) on the Standard plan or above, which the API Management gateway needs.
* Either [HashiCorp Terraform](https://terraform.io) or [OpenTofu](https://opentofu.org).
* Either [Docker](https://www.docker.com) or [Podman](https://podman.io) (recommended).
* [Node.js](https://nodejs.org) 22+, to install the functions' dependencies.
* [jq](https://jqlang.org), which some of the commands below use to read Terraform's JSON outputs.
* The Locally Plugin for `Microsoft.ApiManagement` installed (`locally plugin install --name Microsoft.ApiManagement`).
* The Locally Plugin for `Microsoft.Storage` installed (`locally plugin install --name Microsoft.Storage`).
* The Locally Plugin for `Microsoft.Web` installed (`locally plugin install --name Microsoft.Web`).
* The Locally Plugin for `Microsoft.OperationalInsights` installed (`locally plugin install --name Microsoft.OperationalInsights`).
* The Locally Plugin for `Microsoft.Insights` installed (`locally plugin install --name Microsoft.Insights`).

## Running the example

First, make sure your container runtime (Docker or Podman) is running, then start Locally:

```bash
locally build
```

Each app is deployed from a zip that Terraform builds from its directory. The Function Apps' zips have to include their dependencies, so install those first (the Web App has none):

```bash
(cd functions/catalog && npm install)
(cd functions/orders && npm install)
```

With Locally running, open another terminal and initialise Terraform. This downloads the providers and sets up the module:

```bash
cd environments/locally
terraform init
```

> [!NOTE]
> You can use OpenTofu instead by running `tofu` wherever this says `terraform`.

Once Terraform is initialised, provision the example:

```bash
locally run terraform apply
```

A single apply creates everything: the three apps with their code, the API Management instance with its backends, APIs, operations, policies and product, and a subscription. When it finishes, the URLs are in the outputs:

```
gateway_url  = "https://locally-example-apimback-apim.switchboard.locally:5670"
products_url = "https://locally-example-apimback-apim.switchboard.locally:5670/catalog/products"
orders_url   = "https://locally-example-apimback-apim.switchboard.locally:5670/orders/orders"
reviews_url  = "https://locally-example-apimback-apim.switchboard.locally:5670/reviews/reviews"
```

The subscription key is a sensitive output. Read it into a variable, along with the URLs:

```bash
KEY=$(locally run terraform output -raw subscription_key)
PRODUCTS=$(locally run terraform output -raw products_url)
ORDERS=$(locally run terraform output -raw orders_url)
REVIEWS=$(locally run terraform output -raw reviews_url)
```

Then call all three apps through the gateway:

```bash
curl -H "Ocp-Apim-Subscription-Key: $KEY" "$PRODUCTS"
curl -H "Ocp-Apim-Subscription-Key: $KEY" "$PRODUCTS/mug"

curl -H "Ocp-Apim-Subscription-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"productId": "mug", "quantity": 2}' "$ORDERS"
curl -H "Ocp-Apim-Subscription-Key: $KEY" "$ORDERS"

curl -H "Ocp-Apim-Subscription-Key: $KEY" "$REVIEWS?productId=mug"
curl -H "Ocp-Apim-Subscription-Key: $KEY" -H 'Content-Type: application/json' \
  -d '{"productId": "mug", "rating": 4, "text": "Bigger than it looks."}' "$REVIEWS"
```

Each response says `"via": "locally-example-apimback-apim"`, which shows the request came through the gateway.

### What the gateway refuses

```bash
# No subscription key: 401 from API Management
curl -i "$PRODUCTS"

# A method or path with no matching operation: 404 from API Management
curl -i -X DELETE -H "Ocp-Apim-Subscription-Key: $KEY" "$ORDERS"

# Going around the gateway: 401 from each app, which wants its credential
APPS=$(locally run terraform output -json app_urls)
curl -i "$(echo "$APPS" | jq -r .catalog)/products"
curl -i "$(echo "$APPS" | jq -r .orders)/orders"
curl -i "$(echo "$APPS" | jq -r .reviews)/reviews"

# More than 20 calls in a minute: 429 from API Management, with a Retry-After header
for i in $(seq 1 25); do
  curl -s -o /dev/null -w "%{http_code}\n" -H "Ocp-Apim-Subscription-Key: $KEY" "$PRODUCTS"
done
```

### Seeing what the gateway did

Send `Ocp-Apim-Trace: true` with a request to have the gateway trace it:

```bash
curl -H "Ocp-Apim-Subscription-Key: $KEY" -H "Ocp-Apim-Trace: true" "$PRODUCTS"
```

The trace is in the Requests page of the API Management instance's admin UI, at `https://locally-example-apimback-apim-admin.switchboard.locally:5670/_ui/requests`. Open the request to see each step: the policies that ran, the backend the request went to (with its `resource_id`), the credentials that backend added (by name, never their values), and the app's answer.

The functions send their logs to a Log Analytics Workspace. You can query them in [the Monitoring section of the Locally Dashboard](https://localhost:5678/monitoring/components) by running:

```
FunctionAppLogs | order by TimeGenerated desc
```

## Notes

The orders and reviews apps keep their data in memory, so it's lost when they restart. This keeps the example focused on API Management and the apps behind it. A real app would store it in a database.

Every policy keeps `<base />` in each section, so the product's rate limit (the outer scope) runs before the API's own policy. Locally runs the `inbound` section only, which is all this example uses: `outbound` and `backend` policies aren't applied yet.

Backends can also carry query-string credentials (`credentials.query`) and an `Authorization` header (`credentials.authorization`), and Locally's gateway applies those too. Client-certificate credentials, circuit breakers and load-balanced backend pools aren't supported by Locally yet.

[`example-api-management-function-apps`](https://github.com/locallybuild/example-api-management-function-apps) shows the other way to front Function Apps: an API `service_url` plus a `set-header` policy that adds the function key.

The rate limit is set by the `rate_limit_calls` and `rate_limit_period` variables on the module.

Terraform writes each package to `.build/<app>-<hash>.zip`, where the hash covers everything in that app's directory. The provider only redeploys the code when `zip_deploy_file` changes, so the hash in the name is what makes an edit to the code (or an `npm install`) reach the app on the next apply.

## Tearing it down

```bash
cd environments/locally
locally run terraform destroy
```
