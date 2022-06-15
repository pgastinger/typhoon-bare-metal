// Configure the matchbox provider
provider "matchbox" {
  endpoint    = "matchbox.secitec.net:8081"
  client_cert = file("tls/client.crt")
  client_key  = file("tls/client.key")
  ca          = file("tls/ca.crt")
}

provider "ct" {}

terraform {
  required_providers {
    ct = {
      source  = "poseidon/ct"
      version = "0.10.0"
    }
    matchbox = {
      source = "poseidon/matchbox"
      version = "0.5.0"
    }
  }
}