project_name             = "crc"
region                   = "eu-central-1"
environment              = "prod"
zone_name                = "jorislefondeur.com"
domain_name              = "jorislefondeur.com"
acm_wildcard             = "*.jorislefondeur.com"
frontend_origin_id       = "frontend-origin"
cloudfront_min_ttl       = 0
cloudfront_default_ttl   = 0 # TODO: use 3600
cloudfront_max_ttl       = 86400
verified_origin_rotation = 14
lambda_log_retention     = 30

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
