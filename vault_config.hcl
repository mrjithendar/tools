listener "tcp" {
    address = "0.0.0.0:8200"
    tls_disabled = true
}

storage "file" {
    path = "./vault/data"
    node_id  = "node1"
}

ui = true
api_addr = "http://localhost:8200"
cluster_addr = "http://127.0.0.1:8201"
disable_mlock = true


# storage: This is the physical backend that Vault uses for storage.

# listener: One or more listeners determine how Vault listens for API requests. The example above listens on localhost port 8200 without TLS.

# api_addr: Specifies the address to advertise to route client requests.

# cluster_addr: Indicates the address and port to be used for communication between the Vault nodes in a cluster.