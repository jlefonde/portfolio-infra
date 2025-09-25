region                 = "eu-central-1"
environment            = "prod"
domain_name            = "jorislefondeur.com"
acm_wildcard           = "*.jorislefondeur.com"
frontend_origin_id     = "frontend-origin"
cloudfront_min_ttl     = 0
cloudfront_default_ttl = 0 # TODO: use 3600
cloudfront_max_ttl     = 86400
