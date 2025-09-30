package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

func main() {
	lambda.Start(func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
		return events.APIGatewayV2HTTPResponse{
			StatusCode: http.StatusServiceUnavailable,
			Headers: map[string]string{
				"Content-Type": "application/json",
			},
			Body: fmt.Sprintf(`{
				"error": "Service Unavailable",
				"message": "Application deployment in progress",
				"timestamp": "%s",
				"environment": "%s"
			}`, time.Now().UTC().Format(time.RFC3339), os.Getenv("ENVIRONMENT")),
		}, nil
	})
}
