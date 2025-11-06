package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

type Authorizer struct {
	awsConfig      aws.Config
	secretsManager *secretsmanager.Client
}

func NewAuthorizer() (*Authorizer, error) {
	awsConfig, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		return nil, fmt.Errorf("failed to load default config: %w", err)
	}

	return &Authorizer{
		awsConfig:      awsConfig,
		secretsManager: secretsmanager.NewFromConfig(awsConfig),
	}, nil
}

func (auth *Authorizer) isAuthorized(ctx context.Context, event events.APIGatewayV2CustomAuthorizerV2Request) (*events.APIGatewayV2CustomAuthorizerSimpleResponse, error) {
	log.Println("Authorization request received")

	headerName, found := os.LookupEnv("CLOUDFRONT_ORIGIN_VERIFY_HEADER")
	if !found {
		return nil, errors.New("failed to retrieve CLOUDFRONT_ORIGIN_VERIFY_HEADER environment variable")
	}
	log.Printf("Using header name: %s", headerName)

	secretName, found := os.LookupEnv("SECRET_NAME")
	if !found {
		return nil, errors.New("failed to retrieve SECRET_NAME environment variable")
	}

	log.Printf("Retrieving secret: %s", secretName)
	originVerify, err := auth.secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId: &secretName,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to describe secret: %v", err)
	}
	log.Println("Secret retrieved successfully")

	isAuthorized := false
	headerOriginVerify, found := event.Headers[headerName]
	if !found {
		log.Printf("Authorization header '%s' not found in request\n", headerName)
	} else if headerOriginVerify != *originVerify.SecretString {
		log.Println("Authorization header value does not match secret")
	} else {
		isAuthorized = headerOriginVerify == *originVerify.SecretString
		log.Println("Authorized:", isAuthorized)
	}

	return &events.APIGatewayV2CustomAuthorizerSimpleResponse{
		IsAuthorized: isAuthorized,
	}, nil
}

func main() {
	auth, err := NewAuthorizer()
	if err != nil {
		log.Fatalf("failed to create authorizer: %v", err)
	}

	lambda.Start(auth.isAuthorized)
}
