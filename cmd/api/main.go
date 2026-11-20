package main

import (
	"context"
	"os"

	"github.com/JoelTeoGom/docvault/internal/adapter/auth"
	"github.com/JoelTeoGom/docvault/internal/adapter/repository"
	"github.com/JoelTeoGom/docvault/internal/adapter/storage"
	"github.com/JoelTeoGom/docvault/internal/handler"

	"github.com/aws/aws-lambda-go/lambda"
)

func main() {
	tableName, ok := os.LookupEnv("TABLE")
	secret, secretOk := os.LookupEnv("JWT_SECRET")
	bucket, bucketOk := os.LookupEnv("S3_BUCKET")
	if !ok {
		panic("Need TABLE environment variable")
	}
	if !secretOk {
		panic("Need JWT_SECRET environment variable")
	}
	if !bucketOk {
		panic("Need S3_BUCKET environment variable")
	}

	ctx := context.Background()
	dynamodb := repository.NewDynamoDBStore(ctx, tableName)
	s3 := storage.NewS3Service(ctx, bucket)
	tokenValidator := auth.NewJWTService(secret)

	api := handler.NewAPI(dynamodb, s3)
	router := handler.NewRouter(api, tokenValidator)
	lambda.Start(router.HandleRequest)
}
