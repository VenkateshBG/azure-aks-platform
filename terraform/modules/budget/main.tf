variable "name" { type = string }
variable "resource_group_id" { type = string }
variable "amount" {
  type        = number
  description = "Monthly budget in your BILLING CURRENCY (INR accounts: rupees, not dollars)"
}
variable "contact_emails" { type = list(string) }

resource "azurerm_consumption_budget_resource_group" "this" {
  name              = var.name
  resource_group_id = var.resource_group_id
  amount            = var.amount
  time_grain        = "Monthly"

  time_period {
    # Must be the first day of a month
    start_date = formatdate("YYYY-MM-'01T00:00:00Z'", timestamp())
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      enabled        = true
      threshold      = notification.value
      threshold_type = "Actual"
      operator       = "GreaterThan"
      contact_emails = var.contact_emails
    }
  }

  lifecycle {
    ignore_changes = [time_period] # timestamp() changes every run
  }
}
