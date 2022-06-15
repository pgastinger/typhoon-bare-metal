resource "local_file" "kubeconfig-mercury" {
  content  = module.mercury.kubeconfig-admin
  filename = "kubeconfig"
}