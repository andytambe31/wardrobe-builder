# ---------------------------------------------------------------------------
# "Deploy only through the CI role" guardrail (standalone-account edition).
#
# This account isn't in an AWS Organization, so there's no SCP — and nothing in
# a single account can bind the ROOT user or force FUTURE principals. The next
# best thing: a Deny policy that blocks infrastructure mutation (and IAM changes,
# to stop escalation) for every principal EXCEPT the deploy role and a
# break-glass admin. Attach it to your human IAM group(s) and humans keep read
# access but can no longer create/modify infra out-of-band — only the pipeline's
# deploy role can. Deny always wins, so it holds even over AdministratorAccess.
#
# Created but attached to nothing by default (guardrail_attach_group_names = []),
# so you can review it first, then opt in. The same JSON becomes an SCP verbatim
# if you later enable Organizations — see README.
# ---------------------------------------------------------------------------

locals {
  # Principals allowed to mutate infra: the deploy role, your break-glass admin,
  # and AWS service-linked roles (which legitimately perform some of these
  # actions on AWS's behalf).
  guardrail_exempt_arns = concat(
    [aws_iam_role.ci.arn],
    var.guardrail_break_glass_arns,
    ["arn:aws:iam::${local.acct}:role/aws-service-role/*"],
  )
}

data "aws_iam_policy_document" "deploy_guardrail" {
  statement {
    sid    = "DenyInfraMutationOutsideDeployRole"
    effect = "Deny"

    # Write/mutating actions across the services these stacks manage, plus IAM
    # (so a human can't mint a new role to escape this). Reads (Get/List/
    # Describe) are intentionally NOT denied, so console visibility survives.
    actions = [
      "s3:Put*", "s3:Delete*", "s3:Create*", "s3:Restore*",
      "dynamodb:Create*", "dynamodb:Delete*", "dynamodb:Update*", "dynamodb:Put*",
      "dynamodb:Restore*", "dynamodb:BatchWriteItem", "dynamodb:TagResource", "dynamodb:UntagResource",
      "lambda:Create*", "lambda:Delete*", "lambda:Update*", "lambda:Publish*",
      "lambda:Add*", "lambda:Remove*", "lambda:Put*", "lambda:TagResource", "lambda:UntagResource",
      "cognito-idp:Create*", "cognito-idp:Delete*", "cognito-idp:Update*", "cognito-idp:Set*",
      "apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE",
      "cloudfront:Create*", "cloudfront:Delete*", "cloudfront:Update*",
      "cloudfront:TagResource", "cloudfront:UntagResource", "cloudfront:Associate*", "cloudfront:Copy*",
      "sns:Create*", "sns:Delete*", "sns:Set*", "sns:Subscribe", "sns:Unsubscribe",
      "sns:Add*", "sns:Remove*", "sns:TagResource", "sns:UntagResource",
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:SetAlarmState",
      "cloudwatch:EnableAlarmActions", "cloudwatch:DisableAlarmActions",
      "cloudwatch:TagResource", "cloudwatch:UntagResource",
      "logs:Create*", "logs:Delete*", "logs:Put*", "logs:TagResource",
      "logs:UntagResource", "logs:Associate*",
      "budgets:ModifyBudget",
      "iam:Create*", "iam:Delete*", "iam:Update*", "iam:Put*", "iam:Attach*",
      "iam:Detach*", "iam:Add*", "iam:Remove*", "iam:Set*", "iam:TagRole",
      "iam:UntagRole", "iam:TagUser", "iam:UntagUser", "iam:TagPolicy", "iam:UntagPolicy",
      "iam:Upload*", "iam:ChangePassword", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
    ]
    resources = ["*"]

    # The escape hatch: exempt the deploy role, break-glass admin, and SLRs.
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.guardrail_exempt_arns
    }
  }
}

resource "aws_iam_policy" "deploy_guardrail" {
  name        = "${var.project}-deploy-only-guardrail"
  description = "Deny infra mutation + IAM changes for everyone except the ${var.project} deploy role and break-glass admin. Attach to human IAM groups."
  policy      = data.aws_iam_policy_document.deploy_guardrail.json
}

# Optional attachment to human IAM groups. Empty by default = created but NOT
# enforced, so you can review before opting in.
resource "aws_iam_group_policy_attachment" "deploy_guardrail" {
  for_each   = toset(var.guardrail_attach_group_names)
  group      = each.value
  policy_arn = aws_iam_policy.deploy_guardrail.arn
}
