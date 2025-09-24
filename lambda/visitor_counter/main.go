package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
)

type DbContext struct {
	client    *dynamodb.Client
	tableName string
}

var (
	db        DbContext
	tableName string = "VisitorCount"
)

type VisitorCount struct {
	Id    string `json:"id" dynamodbav:"id"`
	Count int    `json:"count" dynamodbav:"count"`
}

func clientError(status int) events.APIGatewayV2HTTPResponse {

	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
	}
}

func serverError(err error) events.APIGatewayV2HTTPResponse {
	log.Println(err.Error())

	return events.APIGatewayV2HTTPResponse{
		StatusCode: http.StatusInternalServerError,
	}
}

func (db DbContext) GetVisitorCount(ctx context.Context, id string) (*VisitorCount, error) {
	key, err := attributevalue.Marshal(id)
	if err != nil {
		return nil, err
	}

	response, err := db.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(db.tableName),
		Key: map[string]types.AttributeValue{
			"id": key,
		},
	})
	if err != nil {
		return nil, err
	}

	if response.Item == nil {
		return nil, nil
	}

	visitorCount := new(VisitorCount)
	err = attributevalue.UnmarshalMap(response.Item, visitorCount)
	if err != nil {
		return nil, err
	}

	return visitorCount, err
}

func processGetVisitorCount(ctx context.Context, req events.APIGatewayV2HTTPRequest) events.APIGatewayV2HTTPResponse {
	id, ok := req.PathParameters["id"]
	if !ok {
		return clientError(http.StatusNotFound)
	}

	visitorCount, err := db.GetVisitorCount(ctx, id)
	if err != nil {
		return serverError(err)
	}

	if visitorCount == nil {
		return clientError(http.StatusNotFound)
	}

	response, err := json.Marshal(visitorCount)
	if err != nil {
		return serverError(err)
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: http.StatusOK,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: string(response),
	}
}

func (db DbContext) IncrementVisitorCount(ctx context.Context, id string) (*dynamodb.UpdateItemOutput, error) {
	key, err := attributevalue.Marshal(id)
	if err != nil {
		return nil, err
	}

	response, err := db.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String(db.tableName),
		Key: map[string]types.AttributeValue{
			"id": key,
		},
		UpdateExpression: aws.String("ADD #count :increment"),
		ExpressionAttributeNames: map[string]string{
			"#count": "count",
		},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":increment": &types.AttributeValueMemberN{Value: "1"},
		},
		ReturnValues: types.ReturnValueUpdatedNew,
	})
	if err != nil {
		return nil, err
	}

	return response, err
}

func processPostVisitorCount(ctx context.Context, req events.APIGatewayV2HTTPRequest) events.APIGatewayV2HTTPResponse {
	id, ok := req.PathParameters["id"]
	if !ok {
		return clientError(http.StatusNotFound)
	}

	updatedCount, err := db.IncrementVisitorCount(ctx, id)
	if err != nil {
		return serverError(err)
	}

	response := new(VisitorCount)
	response.Id = id
	err = attributevalue.UnmarshalMap(updatedCount.Attributes, response)
	if err != nil {
		return serverError(err)
	}

	json, err := json.Marshal(response)
	if err != nil {
		return serverError(err)
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: http.StatusOK,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: string(json),
	}
}

func requestHandler(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	switch req.RequestContext.HTTP.Method {
	case "GET":
		return processGetVisitorCount(ctx, req), nil
	case "POST":
		return processPostVisitorCount(ctx, req), nil
	default:
		return clientError(http.StatusMethodNotAllowed), nil
	}
}

func init() {
	cfg, err := config.LoadDefaultConfig(context.TODO(), config.WithRegion("us-east-1"))
	if err != nil {
		panic(fmt.Sprintf("failed to config: %v", err))
	}

	db.client = dynamodb.NewFromConfig(cfg)
	db.tableName = tableName
}

func main() {
	lambda.Start(requestHandler)
}
