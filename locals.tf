# use local vars for EKS module
locals {
  cluster_name = "terraform-eks-dev"
  cluster_version = "1.19"
  config_output_path = "./"
  map_roles_count = 1
  tags = {
    Environment = "development"
  }
}
