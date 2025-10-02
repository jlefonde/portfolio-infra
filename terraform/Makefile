build-boostrap-lambda:
	cd lambda/bootstrap && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o bootstrap main.go

build-verified-origin-rotation-lambda:
	cd lambda/rotate_verified_origin/cmd && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o bootstrap main.go 

init-prod:
	cd environments/prod && terraform init

plan-prod:
	cd environments/prod && terraform plan

apply-prod:
	cd environments/prod && terraform apply

destroy-prod:
	cd environments/prod && terraform destroy