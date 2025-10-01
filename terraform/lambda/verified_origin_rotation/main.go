package main

import (
	"context"
	"fmt"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

type AWSContext struct {
	secretsManager *secretsmanager.Client
	// cloudFront     *cloudfront.CloudFront
}

var (
	aws AWSContext
)

func rotateVerifiedOrigin(ctx context.Context, req events.SecretsManagerSecretRotationEvent) (bool, error) {
	excludePunctuation := true
	passwordLength := int64(32)
	secretId := "verified-origin-prod"

	password_output, err := aws.secretsManager.GetRandomPassword(ctx, &secretsmanager.GetRandomPasswordInput{
		ExcludePunctuation: &excludePunctuation,
		PasswordLength:     &passwordLength,
	})
	if err != nil {
		return false, err
	}

	aws.secretsManager.UpdateSecret(ctx, &secretsmanager.UpdateSecretInput{
		SecretId:     &secretId,
		SecretString: password_output.RandomPassword,
	})

	return true, nil
}

func init() {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion("eu-central-1"))
	if err != nil {
		panic(fmt.Sprintf("failed to config: %v", err))
	}

	aws.secretsManager = secretsmanager.NewFromConfig(cfg)
	// aws.cloudFront = cloudfront.
}

func main() {
	lambda.Start(rotateVerifiedOrigin)
}
