# Optional role for the external Hetzner workload. No access keys are generated.
# Supply an existing IAM user/role ARN; an external pod cannot assume an AWS role
# without a source credential or federation mechanism.

data "aws_caller_identity" "bedrock" {}

resource "aws_iam_role" "shopping_agent_bedrock" {
  count                = local.bedrock_enabled ? 1 : 0
  name                 = "${local.name_prefix}-${var.environment}-shopping-agent-bedrock"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = sort(tolist(var.bedrock_trusted_principal_arns)) }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "shopping_agent_bedrock" {
  count = local.bedrock_enabled ? 1 : 0
  name  = "invoke-selected-bedrock-profile"
  role  = aws_iam_role.shopping_agent_bedrock[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeSelectedProfile"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = local.bedrock_profile_arn
      },
      {
        Sid    = "InvokeProfileDestinationModels"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        # Geographic inference can route among US destinations. Restrict both
        # the exact model and the profile; direct foundation-model calls fail.
        Resource = "arn:aws:bedrock:us-*::foundation-model/${var.bedrock_model_id}"
        Condition = {
          StringEquals = { "bedrock:InferenceProfileArn" = local.bedrock_profile_arn }
        }
      }
    ]
  })
}
