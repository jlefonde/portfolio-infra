terraform {
  backend "s3" {
    key          = "terraform.tfstate"
    region       = "eu-central-1"
    bucket       = "crc-tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
