resource "aws_apigatewayv2_api" "primary" {
  name            = var.api_name
  description     = var.api_description
  protocol_type   = var.api_protocol_type
  ip_address_type = var.api_ip_address_type
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.primary.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "this" {
  for_each = var.routes

  api_id                 = aws_apigatewayv2_api.primary.id
  integration_type       = each.value.integration.type
  integration_method     = each.value.integration.method
  integration_uri        = each.value.integration.uri
  payload_format_version = each.value.integration.payload_format_version
}

resource "aws_apigatewayv2_authorizer" "origin_verify" {
  for_each = var.authorizers

  api_id                            = aws_apigatewayv2_api.primary.id
  authorizer_type                   = each.value.authorizer_type
  authorizer_uri                    = each.value.authorizer_uri
  identity_sources                  = each.value.identity_sources
  name                              = each.value.name
  authorizer_payload_format_version = each.value.authorizer_payload_format_version
  enable_simple_responses           = each.value.enable_simple_responses
}

resource "aws_apigatewayv2_route" "routes" {
  for_each = var.routes

  api_id    = aws_apigatewayv2_api.primary.id
  route_key = each.key

  authorization_type = each.value.authorization_type
  authorizer_id      = each.value.authorizer_key != null ? aws_apigatewayv2_authorizer.origin_verify[each.value.authorizer_key].id : null

  target = "integrations/${aws_apigatewayv2_integration.this[each.key].id}"
}
