module "eks" {
  cluster_version           = local.cluster_version
  source                    = "terraform-aws-modules/eks/aws"
  cluster_name              = local.cluster_name
  subnets                   = module.vpc.private_subnets
  cluster_security_group_id = aws_security_group.cluster_security_group.id
  write_kubeconfig          = false
  vpc_id                    = module.vpc.vpc_id

  worker_groups = [
    {
      name                 = "worker-1-19"
      instance_type        = "t2.small"
      ami_id               = aws_ami_copy.eks_worker_1_19.id
      additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
      asg_desired_capacity = "2"
    },
  ]
}

data "aws_ami" "eks_worker_base_1_18" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-1.18-v*"]
  }
  most_recent = true
  # Owner ID of AWS EKS team
  owners = ["602401143452"]
}

resource "aws_ami_copy" "eks_worker_1_18" {
  name              = "${data.aws_ami.eks_worker_base_1_18.name}-encrypted"
  description       = "Encrypted version of EKS worker AMI"
  source_ami_id     = data.aws_ami.eks_worker_base_1_18.id
  source_ami_region = "eu-central-1"
  encrypted         = true

  tags = {
    Name = "${data.aws_ami.eks_worker_base_1_18.name}-encrypted"
  }
}

data "aws_ami" "eks_worker_base_1_19" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-1.19-v*"]
  }
  most_recent = true
  # Owner ID of AWS EKS team
  owners = ["602401143452"]
}

resource "aws_ami_copy" "eks_worker_1_19" {
  name              = "${data.aws_ami.eks_worker_base_1_19.name}-encrypted"
  description       = "Encrypted version of EKS worker AMI"
  source_ami_id     = data.aws_ami.eks_worker_base_1_19.id
  source_ami_region = "eu-central-1"
  encrypted         = true

  tags = {
    Name = "${data.aws_ami.eks_worker_base_1_19.name}-encrypted"
  }
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}