package secret

import (
	"context"
	"fmt"
	"log"

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

func NewSecretRotator() (*SecretRotator, error) {
	awsConfig, err := config.LoadDefaultConfig(context.TODO())
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
	}, nil
}

func (sr *SecretRotator) SetSetSecretFunc(fn func(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error)) {
	sr.setSecret = fn
}

func (sr *SecretRotator) SetTestSecretFunc(fn func(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error)) {
	sr.testSecret = fn
}

func (sr *SecretRotator) GetSecretsManager() *secretsmanager.Client {
	return sr.secretsManager
}

func (sr *SecretRotator) GetAWSConfig() aws.Config {
	return sr.awsConfig
}

func (sr *SecretRotator) createSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
	log.Printf("Checking for AWSCURRENT version")
	_, err := sr.secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId:     &event.SecretID,
		VersionStage: aws.String("AWSCURRENT"),
	})
	if err != nil {
		log.Printf("No AWSCURRENT version found, skipping creation")
		return true, nil
	}

	log.Printf("Checking for existing AWSPENDING version")
	_, err = sr.secretsManager.GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId:     &event.SecretID,
		VersionId:    &event.ClientRequestToken,
		VersionStage: aws.String("AWSPENDING"),
	})
	if err == nil {
		log.Printf("AWSPENDING version already exists, skipping creation")
		return true, nil
	}

	log.Printf("Generating new random password")
	passwordOutput, err := sr.secretsManager.GetRandomPassword(ctx, sr.randomPasswordInput)
	if err != nil {
		return false, fmt.Errorf("failed to generate random password: %w", err)
	}

	log.Printf("Storing new secret with AWSPENDING stage")
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

	log.Printf("Successfully created AWSPENDING secret version")
	return true, nil
}

func (sr *SecretRotator) finishSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
	log.Printf("Describing secret to check version stages")
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
					log.Printf("Version already marked as AWSCURRENT, rotation complete")
					return true, nil
				}

				currentVersionId = versionId
				break
			}
		}
	}

	log.Printf("Promoting AWSPENDING to AWSCURRENT")
	_, err = sr.secretsManager.UpdateSecretVersionStage(ctx, &secretsmanager.UpdateSecretVersionStageInput{
		SecretId:            &event.SecretID,
		VersionStage:        aws.String("AWSCURRENT"),
		MoveToVersionId:     &event.ClientRequestToken,
		RemoveFromVersionId: &currentVersionId,
	})
	if err != nil {
		return false, fmt.Errorf("failed to update secret version stage: %w", err)
	}

	log.Printf("Successfully completed secret rotation")
	return true, nil
}

func (sr *SecretRotator) RotateSecret(ctx context.Context, event events.SecretsManagerSecretRotationEvent) (bool, error) {
	switch event.Step {
	case "createSecret":
		log.Printf("Executing step: createSecret")
		return sr.createSecret(ctx, event)
	case "setSecret":
		log.Printf("Executing step: setSecret")
		if sr.setSecret == nil {
			log.Printf("No setSecret function configured, skipping")
			return true, nil
		}

		return sr.setSecret(ctx, event)
	case "testSecret":
		log.Printf("Executing step: testSecret")
		if sr.testSecret == nil {
			log.Printf("No testSecret function configured, skipping")
			return true, nil
		}

		return sr.testSecret(ctx, event)
	case "finishSecret":
		log.Printf("Executing step: finishSecret")
		return sr.finishSecret(ctx, event)
	default:
		return false, fmt.Errorf("invalid step parameter: %s", event.Step)
	}
}
