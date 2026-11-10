module "ssh_key" {
  # source = "../../ssh-key"
  source = "git@github.com:permilche/tfe-tf-modules.git//ssh-key?ref=main" # cannot use variables there so need to hardcode it

  organization = var.organization_name
  name         = "private-registry-management-ws-git-access"
  key          = var.ssh_private_key
}