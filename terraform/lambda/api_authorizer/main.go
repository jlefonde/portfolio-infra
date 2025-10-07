package main

import (
	"context"
	"fmt"
	"log"

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

func (auth *Authorizer) isAuthorized(ctx context.Context, event events.APIGatewayV2CustomAuthorizerV2Request) (bool, error) {
	// headerName, found := os.LookupEnv("CLOUDFRONT_ORIGIN_VERIFY_HEADER")
	// if !found {
	// 	return false, errors.New("failed to retrieve CLOUDFRONT_ORIGIN_VERIFY_HEADER environment variable")
	// }

	// secretName, found := os.LookupEnv("SECRET_NAME")
	// if !found {
	// 	return false, errors.New("failed to retrieve SECRET_NAME environment variable")
	// }

	// headerOriginVerify, found := event.Headers[headerName]
	// if !found {
	// 	return false, nil
	// }

	// originVerify, err := auth.secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
	// 	SecretId: &secretName,
	// })
	// if err != nil {
	// 	return false, fmt.Errorf("failed to describe secret: %w", err)
	// }

	// return headerOriginVerify == *originVerify.SecretString, nil
	return true, nil
}

func main() {
	auth, err := NewAuthorizer()
	if err != nil {
		log.Fatal("failed to create authorizer: %w", err)
	}

	lambda.Start(auth.isAuthorized)
}
