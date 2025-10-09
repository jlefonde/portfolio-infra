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

		headerName, found := os.LookupEnv("CLOUDFRONT_ORIGIN_VERIFY_HEADER")
		if !found {
			return false, errors.New("failed to retrieve CLOUDFRONT_ORIGIN_VERIFY_HEADER environment variable")
		}
		log.Printf("Using distribution: %s, origin: %s, header: %s", distributionId, originId, headerName)

		secretsManager := sr.GetSecretsManager()

		log.Printf("Retrieving AWSCURRENT secret version")
		current, err := secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
			SecretId:     &event.SecretID,
			VersionStage: aws.String("AWSCURRENT"),
		})
		if err != nil {
			return false, fmt.Errorf("failed to get current secret: %w", err)
		}

		log.Printf("Retrieving AWSPENDING secret version")
		pending, err := secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
			SecretId:     &event.SecretID,
			VersionId:    &event.ClientRequestToken,
			VersionStage: aws.String("AWSPENDING"),
		})
		if err != nil {
			return false, fmt.Errorf("failed to get pending secret: %w", err)
		}

		cloudFront := cloudfront.NewFromConfig(sr.GetAWSConfig())

		log.Printf("Fetching CloudFront distribution configuration")
		distribution, err := cloudFront.GetDistributionConfig(ctx, &cloudfront.GetDistributionConfigInput{
			Id: &distributionId,
		})
		if err != nil {
			return false, fmt.Errorf("failed to get distribution config: %w", err)
		}

		originIndex := getOriginIndex(distribution.DistributionConfig.Origins.Items, originId)
		if originIndex == -1 {
			return false, fmt.Errorf("failed to get '%s' origin", originId)
		}

		origin := &distribution.DistributionConfig.Origins.Items[originIndex]
		headerIndex := getOriginVerifyHeaderIndex(origin.CustomHeaders.Items, headerName)
		if headerIndex == -1 {
			return false, fmt.Errorf("failed to get '%s' origin header", headerName)
		}

		header := &origin.CustomHeaders.Items[headerIndex]
		log.Printf("Verifying current secret matches CloudFront configuration")
		if header.HeaderValue == nil || *header.HeaderValue != *current.SecretString {
			return false, errors.New("current secret doesn't match cloudfront configuration")
		}

		header.HeaderValue = pending.SecretString

		log.Printf("Updating CloudFront distribution")
		_, err = cloudFront.UpdateDistribution(ctx, &cloudfront.UpdateDistributionInput{
			Id:                 &distributionId,
			DistributionConfig: distribution.DistributionConfig,
			IfMatch:            distribution.ETag,
		})
		if err != nil {
			return false, fmt.Errorf("failed to update distribution: %w", err)
		}

		log.Printf("Successfully updated CloudFront distribution with new secret")
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

		headerName, found := os.LookupEnv("CLOUDFRONT_ORIGIN_VERIFY_HEADER")
		if !found {
			return false, errors.New("failed to retrieve CLOUDFRONT_ORIGIN_VERIFY_HEADER environment variable")
		}
		log.Printf("Using distribution: %s, origin: %s, header: %s", distributionId, originId, headerName)

		secretsManager := sr.GetSecretsManager()

		log.Printf("Retrieving AWSPENDING secret version for validation")
		pending, err := secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
			SecretId:     &event.SecretID,
			VersionId:    &event.ClientRequestToken,
			VersionStage: aws.String("AWSPENDING"),
		})
		if err != nil {
			return false, fmt.Errorf("failed to get pending secret: %w", err)
		}

		cloudFront := cloudfront.NewFromConfig(sr.GetAWSConfig())

		log.Printf("Fetching CloudFront distribution configuration for validation")
		distribution, err := cloudFront.GetDistributionConfig(ctx, &cloudfront.GetDistributionConfigInput{
			Id: &distributionId,
		})
		if err != nil {
			return false, fmt.Errorf("failed to get distribution config: %w", err)
		}

		originIndex := getOriginIndex(distribution.DistributionConfig.Origins.Items, originId)
		if originIndex == -1 {
			return false, fmt.Errorf("failed to get '%s' origin", originId)
		}

		origin := &distribution.DistributionConfig.Origins.Items[originIndex]
		headerIndex := getOriginVerifyHeaderIndex(origin.CustomHeaders.Items, headerName)
		if headerIndex == -1 {
			return false, fmt.Errorf("failed to get '%s' origin header", headerName)
		}

		header := &origin.CustomHeaders.Items[headerIndex]
		log.Printf("Validating pending secret matches CloudFront configuration")
		if header.HeaderValue == nil || *header.HeaderValue != *pending.SecretString {
			return false, errors.New("pending secret doesn't match cloudfront configuration")
		}

		log.Printf("Successfully validated pending secret")
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
