module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.common_name_suffix
  kubernetes_version = "1.32"

  addons = {
    coredns = {}

    eks-pod-identity-agent = {
      before_compute = true
    }

    kube-proxy = {}

    vpc-cni = {
      before_compute = true
    }

    metrics-server = {}
  }

  endpoint_public_access = false
  enable_cluster_creator_admin_permissions = true

  vpc_id                   = local.vpc_id
  subnet_ids               = local.private_subnet_ids
  control_plane_subnet_ids = local.private_subnet_ids

  create_node_security_group = false
  create_security_group      = false

  node_security_group_id = local.eks_node_sg_id
  security_group_id      = local.eks_control_plane_sg_id

  # 🔥 EKS Managed Node Groups
  eks_managed_node_groups = {

    # ✅ BLUE NODE GROUP (primary)
    blue = {
      create = true   # always enabled

      ami_type           = "AL2023_x86_64_STANDARD"
      kubernetes_version = var.eks_nodegroup_blue_version
      instance_types     = ["t3.medium"]

      iam_role_additional_policies = {
        amazonEFS = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
        amazonEBS = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }

      min_size     = 1
      max_size     = 1
      desired_size = 1

      labels = {
        nodegroup = "blue"
      }
    }

    # ✅ GREEN NODE GROUP (upgrade/testing)
    green = {
      create = true   # 🔥 force enabled (no more variable confusion)

      ami_type           = "AL2023_x86_64_STANDARD"
      kubernetes_version = var.eks_nodegroup_green_version
      instance_types     = ["t3.medium"]

      iam_role_additional_policies = {
        amazonEFS = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
        amazonEBS = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }

      min_size     = 1
      max_size     = 2
      desired_size = 1

      # 🔥 prevent scheduling until ready
      taints = {
        upgrade = {
          key    = "upgrade"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      labels = {
        nodegroup = "green"
      }
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.common_name_suffix
    }
  )
}