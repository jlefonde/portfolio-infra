package main

import (
	"log"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jlefonde/crc_infra/verified_origin_rotation/internal/secret"
)

func main() {
	ctx, err := secret.NewSecretRotationContext()
	if err != nil {
		log.Fatal("failed to create AWS context: %w", err)
	}

	lambda.Start(ctx.RotateSecret)
}
