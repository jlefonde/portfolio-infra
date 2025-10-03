package secret

import (
	"context"
	"fmt"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

type SecretRotator struct {
	awsConfig      aws.Config
	secretsManager *secretsmanager.Client

	setSecret           func(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error)
	testSecret          func(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error)
	randomPasswordInput *secretsmanager.GetRandomPasswordInput
}

func NewSecretRotator(setSecret, testSecret func(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error)) (*SecretRotator, error) {
	awsConfig, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion("eu-central-1"))
	if err != nil {
		return nil, fmt.Errorf("failed to load default config: %w", err)
	}

	randomPasswordInput, err := NewRandomPasswordInput()
	if err != nil {
		return nil, fmt.Errorf("failed to create random password input: %w", err)
	}

	return &SecretRotator{
		awsConfig:           awsConfig,
		secretsManager:      secretsmanager.NewFromConfig(awsConfig),
		randomPasswordInput: randomPasswordInput,
		setSecret:           setSecret,
		testSecret:          testSecret,
	}, nil
}

func (sr SecretRotator) createSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
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

	passwordOutput, err := sr.secretsManager.GetRandomPassword(ctx, sr.randomPasswordInput)
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

func (sr SecretRotator) finishSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
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

func (sr SecretRotator) RotateSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
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
