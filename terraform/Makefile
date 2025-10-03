build-boostrap-lambda:
	cd ./lambda/bootstrap && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o ./bootstrap ./main.go

build-rotate-verified-origin-lambda:
	cd ./lambda/rotate_secret && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o ./bin/rotate_verified_origin/bootstrap ./cmd/rotate_verified_origin/main.go 

init-prod:
	cd environments/prod && terraform init

plan-prod:
	cd environments/prod && terraform plan

apply-prod:
	cd environments/prod && terraform apply

destroy-prod:
	cd environments/prod && terraform destroy