project_name                    = "crc"
region                          = "eu-central-1"
environment                     = "Production"
zone_name                       = "jorislefondeur.com"
domain_name                     = "jorislefondeur.com"
acm_wildcard                    = "*.jorislefondeur.com"
frontend_origin_id              = "frontend-origin"
backend_origin_id               = "backend-origin"
cloudfront_origin_verify_header = "x-origin-verify"
origin_verify_rotation          = 14
lambda_log_retention            = 30

dynamodb_tables = {
  visitor_count = {
    hash_key     = "id"
    billing_mode = "PAY_PER_REQUEST"

    attributes = [
      {
        name = "id"
        type = "S"
      }
    ]
  }
}
