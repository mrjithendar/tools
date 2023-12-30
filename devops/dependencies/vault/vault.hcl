# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: BUSL-1.1

# Full configuration options can be found at https://developer.hashicorp.com/vault/docs/configuration

backend "file" {
  path = "/var/lib/vault"
}

api_addr = "http://localhost:8200"

ui = true

disable_mlock = true

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = true
}