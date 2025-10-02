package secret

import (
	"context"
	"errors"
	"fmt"
	"os"
	"slices"

	"github.com/aws/aws-lambda-go/events"
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

var (
	AWS_CURRENT     string = "AWSCURRENT"
	AWS_PENDING     string = "AWSPENDING"
	TRUE            bool   = true
	PASSWORD_LENGTH int64  = 32
)

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
			ExcludePunctuation: &TRUE,
			PasswordLength:     &PASSWORD_LENGTH,
		},
	}, nil
}

func (sr SecretRotationContext) createSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
	_, err := sr.secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId:     &event.SecretID,
		VersionStage: &AWS_CURRENT,
	})
	if err != nil {
		return true, nil
	}

	_, err = sr.secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId:     &event.SecretID,
		VersionId:    &event.ClientRequestToken,
		VersionStage: &AWS_PENDING,
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
		SecretString:       passwordOutput.RandomPassword,
		VersionStages:      []string{AWS_PENDING},
	})
	if err != nil {
		return false, fmt.Errorf("failed to put secret value: %w", err)
	}

	return true, nil
}

func (sr SecretRotationContext) setSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
	// secretValue, err := sr.secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
	// 	SecretId:     &event.SecretID,
	// 	VersionStage: &AWS_CURRENT,
	// })
	// if err != nil {
	// 	return false, fmt.Errorf("failed to get current secret: %w", err)
	// }

	distributionId := os.Getenv("CLOUDFRONT_DISTRIBUTION_ID")
	originId := os.Getenv("ORIGIN_ID")

	distribution, err := sr.cloudFront.GetDistributionConfig(ctx, &cloudfront.GetDistributionConfigInput{
		Id: &distributionId,
	})
	if err != nil {
		return false, fmt.Errorf("failed to get distribution config: %w", err)
	}

	frontendOriginIdx := slices.IndexFunc(distribution.DistributionConfig.Origins.Items, func(origin types.Origin) bool {
		return *origin.Id == originId
	})

	if frontendOriginIdx == -1 {
		return false, errors.New("failed to get frontend origin")
	}

	frontendOrigin := &distribution.DistributionConfig.Origins.Items[frontendOriginIdx]

	verifiedOriginHeader := types.OriginCustomHeader{
		HeaderName:  &event.SecretID,
		HeaderValue: sr.randomPassword,
	}

	headerExists := false
	for i, header := range frontendOrigin.CustomHeaders.Items {
		if *header.HeaderName == event.SecretID {
			frontendOrigin.CustomHeaders.Items[i] = verifiedOriginHeader
			headerExists = true
			break
		}
	}

	if !headerExists {
		frontendOrigin.CustomHeaders.Items = append(frontendOrigin.CustomHeaders.Items, verifiedOriginHeader)
		*frontendOrigin.CustomHeaders.Quantity++
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

	return true, nil
}

func (sr SecretRotationContext) finishSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {

	return true, nil
}

func (sr SecretRotationContext) RotateSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
	switch event.Step {
	case "createSecret":
		return sr.createSecret(ctx, event)
	case "setSecret":
		return sr.setSecret(ctx, event)
	case "testSecret":
		return sr.testSecret(ctx, event)
	case "finishSecret":
		return sr.finishSecret(ctx, event)
	default:
		return false, fmt.Errorf("invalid step parameter: %s", event.Step)
	}
}
