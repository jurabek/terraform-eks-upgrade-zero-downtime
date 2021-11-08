module "eks" {
  cluster_version           = local.cluster_version
  source                    = "terraform-aws-modules/eks/aws"
  cluster_name              = local.cluster_name
  subnets                   = module.vpc.private_subnets
  cluster_security_group_id = aws_security_group.cluster_security_group.id
  write_kubeconfig          = false


  map_roles = [
    {
      rolearn  = aws_iam_role.your_admin_user.arn
      username = "admin"
      groups   = ["system:masters"]
    }
  ]

  tags = {
  }

  vpc_id = module.vpc.vpc_id

  worker_groups = [
    {
      name                          = "on-demand-1-18"
      instance_type                 = "m5d.large"
      ami_id                        = aws_ami_copy.eks_worker_1_18.id
      additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
      asg_max_size                  = var.eks_ondemand_max_size
      asg_min_size                  = 1
      asg_desired_capacity          = var.eks_ondemand_desired_capacity
      kubelet_extra_args            = "--node-labels=node.kubernetes.io/lifecycle=normal"
      suspended_processes           = ["AZRebalance"]
      tags                          = local.autoscaling_tags
    },

    {
      name                          = "on-demand-1-19"
      instance_type                 = "m5d.large"
      ami_id                        = aws_ami_copy.eks_worker_1_19.id
      additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
      asg_max_size                  = var.eks_ondemand_max_size
      asg_min_size                  = 1
      asg_desired_capacity          = var.eks_ondemand_desired_capacity
      kubelet_extra_args            = "--node-labels=node.kubernetes.io/lifecycle=normal"
      suspended_processes           = ["AZRebalance"]
      tags                          = local.autoscaling_tags
    }
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

resource "aws_iam_role_policy_attachment" "workers_autoscaling" {
  count      = var.enable_autoscaling ? 1 : 0
  policy_arn = aws_iam_policy.worker_autoscaling[count.index].arn
  role       = module.eks.worker_iam_role_name
}

resource "aws_iam_policy" "worker_autoscaling" {
  count       = var.enable_autoscaling ? 1 : 0
  name_prefix = "eks-worker-autoscaling-${module.eks.cluster_id}"
  description = "EKS worker node autoscaling policy for cluster ${module.eks.cluster_id}"
  policy      = data.aws_iam_policy_document.worker_autoscaling[count.index].json
}

data "aws_iam_policy_document" "worker_autoscaling" {
  count = var.enable_autoscaling ? 1 : 0
  statement {
    sid    = "eksWorkerAutoscalingAll"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "eksWorkerAutoscalingOwn"
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${module.eks.cluster_id}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

resource "helm_release" "autoscaler" {
  count      = var.enable_autoscaling ? 1 : 0
  name       = "autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"

  set {
    name  = "rbac.create"
    value = "true"
  }

  set {
    name  = "cloudProvider"
    value = "aws"
  }

  set {
    name  = "awsRegion"
    value = var.region
  }
  set {
    name  = "autoDiscovery.clusterName"
    value = local.cluster_name
  }

  set {
    name  = "autoDiscovery.enabled"
    value = true
  }
}
