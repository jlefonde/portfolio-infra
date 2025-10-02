package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"slices"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/cloudfront"
	"github.com/aws/aws-sdk-go-v2/service/cloudfront/types"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
)

type AWSContext struct {
	secretsManager *secretsmanager.Client
	cloudFront     *cloudfront.Client
}

var (
	awsCtx AWSContext
)

// {
//   "DistributionConfig": {
//     "Origins": {
//       "Items": [
//         {
//           "DomainName": "jorislefondeur.com-frontend.s3.amazonaws.com",
//           "Id": "frontend-origin",
//           "ConnectionAttempts": 3,
//           "ConnectionTimeout": 10,
//           "CustomHeaders": {
//             "Quantity": 0,
//             "Items": null
//           },
//           "CustomOriginConfig": null,
//           "OriginAccessControlId": "E2W8YYZXLNEDO7",
//           "OriginPath": "",
//           "OriginShield": {
//             "Enabled": false,
//             "OriginShieldRegion": null
//           },
//           "ResponseCompletionTimeout": null,
//           "S3OriginConfig": {
//             "OriginAccessIdentity": "",
//             "OriginReadTimeout": 30
//           },
//           "VpcOriginConfig": null
//         }
//       ],
//       "Quantity": 1
//     },
//   }
// }

func rotateVerifiedOrigin(ctx context.Context, req events.SecretsManagerSecretRotationEvent) (bool, error) {
	excludePunctuation := true
	passwordLength := int64(32)
	secretId := os.Getenv("SECRET_ID")
	distributionId := os.Getenv("CLOUDFRONT_DISTRIBUTION_ID")
	originId := os.Getenv("ORIGIN_ID")

	passwordOutput, err := awsCtx.secretsManager.GetRandomPassword(ctx, &secretsmanager.GetRandomPasswordInput{
		ExcludePunctuation: &excludePunctuation,
		PasswordLength:     &passwordLength,
	})
	if err != nil {
		return false, fmt.Errorf("failed to generate random password: %w", err)
	}

	verifiedOriginSecret := fmt.Sprintf(`{"verified_origin": "%s"}`, *passwordOutput.RandomPassword)
	_, err = awsCtx.secretsManager.UpdateSecret(ctx, &secretsmanager.UpdateSecretInput{
		SecretId:     &secretId,
		SecretString: &verifiedOriginSecret,
	})
	if err != nil {
		return false, fmt.Errorf("failed to update secret: %w", err)
	}

	distribution, err := awsCtx.cloudFront.GetDistributionConfig(ctx, &cloudfront.GetDistributionConfigInput{
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
		HeaderName:  &secretId,
		HeaderValue: passwordOutput.RandomPassword,
	}

	headerExists := false
	for i, header := range frontendOrigin.CustomHeaders.Items {
		if *header.HeaderName == secretId {
			frontendOrigin.CustomHeaders.Items[i] = verifiedOriginHeader
			headerExists = true
			break
		}
	}

	if !headerExists {
		frontendOrigin.CustomHeaders.Items = append(frontendOrigin.CustomHeaders.Items, verifiedOriginHeader)
		*frontendOrigin.CustomHeaders.Quantity++
	}

	_, err = awsCtx.cloudFront.UpdateDistribution(ctx, &cloudfront.UpdateDistributionInput{
		Id:                 &distributionId,
		DistributionConfig: distribution.DistributionConfig,
		IfMatch:            distribution.ETag,
	})
	if err != nil {
		return false, fmt.Errorf("failed to update distribution: %w", err)
	}

	return true, nil
}

func init() {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion("eu-central-1"))
	if err != nil {
		panic(fmt.Sprintf("failed to config: %v", err))
	}

	awsCtx.secretsManager = secretsmanager.NewFromConfig(cfg)
	awsCtx.cloudFront = cloudfront.NewFromConfig(cfg)
}

func main() {
	lambda.Start(rotateVerifiedOrigin)
}
