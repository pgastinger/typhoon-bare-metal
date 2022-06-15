module "mercury" {
  source = "git::https://github.com/poseidon/typhoon//bare-metal/flatcar-linux/kubernetes?ref=v1.24.1"

  # bare-metal
  cluster_name            = "helium"
  matchbox_http_endpoint  = "http://matchbox.secitec.net:8080"
  os_channel              = "flatcar-stable"
  os_version              = "3139.2.2"

  # configuration
  k8s_domain_name    = "node01.secitec.net"
  ssh_authorized_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCeyOuElMC2K8hQ7XRv/ii57Lyh8Q2PWhwiDtZZo588Vjw+TigH+ax692pfYiw6c1aQjeDewvf8PJMjEbt1QLm7PHrbDHELK6GVjhDQKwPppFmEVU8IbFYYDj9I5o2e5bDF0bajotvd1S0kCGChJes+wy++oELcB2FL/5BvjSrP1VvBGD4RX0Km6M978YXm9KFSdToFGuukO/x6RMCELA4NrwPCbl5hy+NPyc6Xi7VUjgUBfugAdqNNFHCA9mNxJVLZ0UaETbgwlUifS7Ensr5a5Dp1AEswd04/SXzFyiUg8IHjRsNM1Y0T1BkJNxT9c6yjMW3XkUUYcjfhzSRQj/N1 peda@peda-desktop"

  # machines
  controllers = [{
    name   = "node01"
    mac    = "52:54:00:19:9e:1a"
    domain = "node01.secitec.net"
  }]
  workers = [
    {
      name   = "node02",
      mac    = "52:54:00:31:8d:a7"
      domain = "node02.secitec.net"
    },
    {
      name   = "node03",
      mac    = "52:54:00:7f:a4:84"
      domain = "node03.secitec.net"
    }    
  ]
}
