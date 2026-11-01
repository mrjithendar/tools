# IAM for the AWS Load Balancer Controller, opt-in because the NLB it creates is billed. The controller, Istio and the
# gateway are Argo CD Applications in eks-argocd/applications; eks-argocd/RUNBOOK.md gives the order.
resource "aws_iam_policy" "eks_load_balancer_controller" {
  count  = local.eks_ingress_enabled ? 1 : 0
  name   = "${local.eks_name}-load-balancer-controller"
  policy = file("${path.module}/policies/aws-load-balancer-controller-v3.6.2.json")
  tags   = local.common_tags
}
resource "aws_iam_role_policy_attachment" "eks_load_balancer_controller" {
  count      = local.eks_ingress_enabled ? 1 : 0
  role       = aws_iam_role.eks_load_balancer_controller[0].name
  policy_arn = aws_iam_policy.eks_load_balancer_controller[0].arn
}
resource "aws_eks_pod_identity_association" "load_balancer_controller" {
  count           = local.eks_ingress_enabled ? 1 : 0
  cluster_name    = aws_eks_cluster.main[0].name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.eks_load_balancer_controller[0].arn
  tags            = local.common_tags
}
