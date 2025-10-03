package main

import (
	"context"
	"log"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/service/cloudfront/types"
	"github.com/jlefonde/crc_infra/rotate_secret/internal/secret"
)

func getOrigin(origins []types.Origin, originId string) *types.Origin {
	for _, origin := range origins {
		if *origin.Id == originId {
			return &origin
		}
	}

	return nil
}

func getOriginVerifyHeader(headers []types.OriginCustomHeader, headerName string) *types.OriginCustomHeader {
	for _, header := range headers {
		if *header.HeaderName == headerName {
			return &header
		}
	}

	return nil
}

func setSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
	return true, nil
}

func testSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
	return true, nil
}

func main() {
	sr, err := secret.NewSecretRotator(setSecret, testSecret)
	if err != nil {
		log.Fatal("failed to create AWS context: %w", err)
	}

	lambda.Start(sr.RotateSecret)
}
