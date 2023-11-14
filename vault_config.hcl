backend "file" {
  path = "/var/lib/vault"
}

api_addr = "http://localhost:8200"

ui = true

disable_mlock = true

listener "tcp" {
  address       = "http://0.0.0.0:8200"
  tls_disable   = true
}