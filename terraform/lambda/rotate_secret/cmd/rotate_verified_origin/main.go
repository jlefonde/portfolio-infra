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
	"github.com/aws/aws-sdk-go-v2/service/cloudfront"
	"github.com/aws/aws-sdk-go-v2/service/cloudfront/types"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/jlefonde/crc_infra/rotate_secret/internal/secret"
)

func getOriginIndex(origins []types.Origin, originId string) int {
	for i, origin := range origins {
		if *origin.Id == originId {
			return i
		}
	}

	return -1
}

func getOriginVerifyHeaderIndex(headers []types.OriginCustomHeader, headerName string) int {
	for i, header := range headers {
		if *header.HeaderName == headerName {
			return i
		}
	}

	return -1
}

func setSecret(sr *secret.SecretRotator) func(context.Context, events.SecretsManagerSecretRotationEvent) (bool, error) {
	return func(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
		distributionId, found := os.LookupEnv("CLOUDFRONT_DISTRIBUTION_ID")
		if !found {
			return false, errors.New("failed to retrieve CLOUDFRONT_DISTRIBUTION_ID environment variable")
		}

		originId, found := os.LookupEnv("CLOUDFRONT_ORIGIN_ID")
		if !found {
			return false, errors.New("failed to retrieve CLOUDFRONT_ORIGIN_ID environment variable")
		}

		headerName, found := os.LookupEnv("CLOUDFRONT_ORIGIN_HEADER_NAME")
		if !found {
			return false, errors.New("failed to retrieve CLOUDFRONT_ORIGIN_HEADER_NAME environment variable")
		}

		secretsManager := sr.GetSecretsManager()

		current, err := secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
			SecretId:     &event.SecretID,
			VersionStage: aws.String("AWSCURRENT"),
		})
		if err != nil {
			return false, fmt.Errorf("failed to get current secret: %w", err)
		}

		pending, err := secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
			SecretId:     &event.SecretID,
			VersionId:    &event.ClientRequestToken,
			VersionStage: aws.String("AWSPENDING"),
		})
		if err != nil {
			return false, fmt.Errorf("failed to get pending secret: %w", err)
		}

		cloudFront := cloudfront.NewFromConfig(sr.GetAWSConfig())

		distribution, err := cloudFront.GetDistributionConfig(ctx, &cloudfront.GetDistributionConfigInput{
			Id: &distributionId,
		})
		if err != nil {
			return false, fmt.Errorf("failed to get distribution config: %w", err)
		}

		originIndex := getOriginIndex(distribution.DistributionConfig.Origins.Items, originId)
		if originIndex == -1 {
			return false, errors.New("failed to get frontend origin")
		}

		headerIndex := getOriginVerifyHeaderIndex(distribution.DistributionConfig.Origins.Items[originIndex].CustomHeaders.Items, headerName)
		if headerIndex == -1 ||
			distribution.DistributionConfig.Origins.Items[originIndex].CustomHeaders.Items[headerIndex].HeaderValue == nil ||
			*distribution.DistributionConfig.Origins.Items[originIndex].CustomHeaders.Items[headerIndex].HeaderValue != *current.SecretString {
			return false, errors.New("current secret doesn't match cloudfront configuration")
		}

		distribution.DistributionConfig.Origins.Items[originIndex].CustomHeaders.Items[headerIndex].HeaderValue = pending.SecretString

		_, err = cloudFront.UpdateDistribution(ctx, &cloudfront.UpdateDistributionInput{
			Id:                 &distributionId,
			DistributionConfig: distribution.DistributionConfig,
			IfMatch:            distribution.ETag,
		})

		if err != nil {
			return false, fmt.Errorf("failed to update distribution: %w", err)
		}

		return true, nil
	}
}

func testSecret(sr *secret.SecretRotator) func(context.Context, events.SecretsManagerSecretRotationEvent) (bool, error) {
	return func(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
		distributionId, found := os.LookupEnv("CLOUDFRONT_DISTRIBUTION_ID")
		if !found {
			return false, errors.New("failed to retrieve CLOUDFRONT_DISTRIBUTION_ID environment variable")
		}

		originId, found := os.LookupEnv("CLOUDFRONT_ORIGIN_ID")
		if !found {
			return false, errors.New("failed to retrieve CLOUDFRONT_ORIGIN_ID environment variable")
		}

		headerName, found := os.LookupEnv("CLOUDFRONT_ORIGIN_HEADER_NAME")
		if !found {
			return false, errors.New("failed to retrieve CLOUDFRONT_ORIGIN_HEADER_NAME environment variable")
		}

		secretsManager := sr.GetSecretsManager()

		pending, err := secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
			SecretId:     &event.SecretID,
			VersionId:    &event.ClientRequestToken,
			VersionStage: aws.String("AWSPENDING"),
		})
		if err != nil {
			return false, fmt.Errorf("failed to get pending secret: %w", err)
		}

		cloudFront := cloudfront.NewFromConfig(sr.GetAWSConfig())

		distribution, err := cloudFront.GetDistributionConfig(ctx, &cloudfront.GetDistributionConfigInput{
			Id: &distributionId,
		})
		if err != nil {
			return false, fmt.Errorf("failed to get distribution config: %w", err)
		}

		originIndex := getOriginIndex(distribution.DistributionConfig.Origins.Items, originId)
		if originIndex == -1 {
			return false, errors.New("failed to get frontend origin")
		}

		headerIndex := getOriginVerifyHeaderIndex(distribution.DistributionConfig.Origins.Items[originIndex].CustomHeaders.Items, headerName)
		if headerIndex == -1 {
			return false, errors.New("failed to get verified origin header")
		}

		if distribution.DistributionConfig.Origins.Items[originIndex].CustomHeaders.Items[headerIndex].HeaderValue == nil ||
			*distribution.DistributionConfig.Origins.Items[originIndex].CustomHeaders.Items[headerIndex].HeaderValue != *pending.SecretString {
			return false, errors.New("pending secret doesn't match cloudfront configuration")
		}

		return true, nil
	}
}

func main() {
	sr, err := secret.NewSecretRotator()
	if err != nil {
		log.Fatal("failed to create secret rotator: %w", err)
	}

	sr.SetSetSecretFunc(setSecret(sr))
	sr.SetTestSecretFunc(testSecret(sr))

	lambda.Start(sr.RotateSecret)
}
