package secret

import (
	"context"
	"errors"
	"fmt"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudfront"
	"github.com/aws/aws-sdk-go-v2/service/cloudfront/types"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

type SecretRotationContext struct {
	secretsManager *secretsmanager.Client
	// TODO: no necessarly cloudfront
	cloudFront *cloudfront.Client

	passwordInput secretsmanager.GetRandomPasswordInput
}

func NewSecretRotationContext() (*SecretRotationContext, error) {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion("eu-central-1"))
	if err != nil {
		return nil, fmt.Errorf("failed to load default config: %w", err)
	}

	return &SecretRotationContext{
		secretsManager: secretsmanager.NewFromConfig(cfg),
		cloudFront:     cloudfront.NewFromConfig(cfg),
		passwordInput: secretsmanager.GetRandomPasswordInput{
			// TODO: read from os env
			ExcludePunctuation: aws.Bool(true),
			PasswordLength:     aws.Int64(32),
		},
	}, nil
}

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

func (sr SecretRotationContext) createSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
	_, err := sr.secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId:     &event.SecretID,
		VersionStage: aws.String("AWSCURRENT"),
	})
	if err != nil {
		return true, nil
	}

	_, err = sr.secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId:     &event.SecretID,
		VersionId:    &event.ClientRequestToken,
		VersionStage: aws.String("AWSPENDING"),
	})
	if err == nil {
		return true, nil
	}

	passwordOutput, err := sr.secretsManager.GetRandomPassword(ctx, &sr.passwordInput)
	if err != nil {
		return false, fmt.Errorf("failed to generate random password: %w", err)
	}

	_, err = sr.secretsManager.PutSecretValue(ctx, &secretsmanager.PutSecretValueInput{
		SecretId:           &event.SecretID,
		ClientRequestToken: &event.ClientRequestToken,
		RotationToken:      &event.RotationToken,
		SecretString:       passwordOutput.RandomPassword,
		VersionStages:      []string{"AWSPENDING"},
	})
	if err != nil {
		return false, fmt.Errorf("failed to put secret value: %w", err)
	}

	return true, nil
}

func (sr SecretRotationContext) setSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
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

	current, err := sr.secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId:     &event.SecretID,
		VersionStage: aws.String("AWSCURRENT"),
	})
	if err != nil {
		return false, fmt.Errorf("failed to get current secret, abandoning rotation: %w", err)
	}

	pending, err := sr.secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId:     &event.SecretID,
		VersionId:    &event.ClientRequestToken,
		VersionStage: aws.String("AWSPENDING"),
	})
	if err != nil {
		return false, fmt.Errorf("failed to get pending secret: %w", err)
	}

	distribution, err := sr.cloudFront.GetDistributionConfig(ctx, &cloudfront.GetDistributionConfigInput{
		Id: &distributionId,
	})
	if err != nil {
		return false, fmt.Errorf("failed to get distribution config: %w", err)
	}

	frontendOrigin := getOrigin(distribution.DistributionConfig.Origins.Items, originId)
	if frontendOrigin == nil {
		return false, errors.New("failed to get frontend origin")
	}

	originVerifyHeader := getOriginVerifyHeader(frontendOrigin.CustomHeaders.Items, headerName)
	if originVerifyHeader == nil {
		frontendOrigin.CustomHeaders.Items = append(frontendOrigin.CustomHeaders.Items, types.OriginCustomHeader{
			HeaderName:  &headerName,
			HeaderValue: pending.SecretString,
		})

		*frontendOrigin.CustomHeaders.Quantity++
	} else {
		if originVerifyHeader.HeaderValue == nil || *originVerifyHeader.HeaderValue != *current.SecretString {
			return false, errors.New("current secret doesn't match cloudfront configuration, abandoning rotation")
		}

		originVerifyHeader.HeaderValue = pending.SecretString
	}

	_, err = sr.cloudFront.UpdateDistribution(ctx, &cloudfront.UpdateDistributionInput{
		Id:                 &distributionId,
		DistributionConfig: distribution.DistributionConfig,
		IfMatch:            distribution.ETag,
	})
	if err != nil {
		return false, fmt.Errorf("failed to update distribution: %w", err)
	}

	return true, nil
}

func (sr SecretRotationContext) testSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
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

	pending, err := sr.secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId:     &event.SecretID,
		VersionId:    &event.ClientRequestToken,
		VersionStage: aws.String("AWSPENDING"),
	})
	if err != nil {
		return false, fmt.Errorf("failed to get pending secret: %w", err)
	}

	distribution, err := sr.cloudFront.GetDistributionConfig(ctx, &cloudfront.GetDistributionConfigInput{
		Id: &distributionId,
	})
	if err != nil {
		return false, fmt.Errorf("failed to get distribution config: %w", err)
	}

	frontendOrigin := getOrigin(distribution.DistributionConfig.Origins.Items, originId)
	if frontendOrigin == nil {
		return false, errors.New("failed to get frontend origin")
	}

	originVerifyHeader := getOriginVerifyHeader(frontendOrigin.CustomHeaders.Items, headerName)
	if originVerifyHeader == nil {
		return false, errors.New("failed to get verified origin header")
	}

	if originVerifyHeader.HeaderValue != pending.SecretString {
		return false, errors.New("pending secret doesn't match cloudfront configuration, abandoning rotation")
	}

	return true, nil
}

func (sr SecretRotationContext) finishSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
	secretDesc, err := sr.secretsManager.DescribeSecret(ctx, &secretsmanager.DescribeSecretInput{
		SecretId: &event.SecretID,
	})
	if err != nil {
		return false, fmt.Errorf("failed to describe secret: %w", err)
	}

	var currentVersionId string
	for versionId, stages := range secretDesc.VersionIdsToStages {
		for _, stage := range stages {
			if stage == "AWSCURRENT" {
				if versionId == event.ClientRequestToken {
					return true, nil
				}

				currentVersionId = versionId
				break
			}
		}
	}

	_, err = sr.secretsManager.UpdateSecretVersionStage(ctx, &secretsmanager.UpdateSecretVersionStageInput{
		SecretId:            &event.SecretID,
		VersionStage:        aws.String("AWSCURRENT"),
		MoveToVersionId:     &event.ClientRequestToken,
		RemoveFromVersionId: &currentVersionId,
	})
	if err != nil {
		return false, fmt.Errorf("failed to update secret version stage: %w", err)
	}

	return true, nil
}

func (sr SecretRotationContext) RotateSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
	switch event.Step {
	case "createSecret":
		return sr.createSecret(ctx, event)
	case "setSecret":
		// return sr.setSecret(ctx, event)
		return true, nil
	case "testSecret":
		// return sr.testSecret(ctx, event)
		return true, nil
	case "finishSecret":
		return sr.finishSecret(ctx, event)
	default:
		return false, fmt.Errorf("invalid step parameter: %s", event.Step)
	}
}
