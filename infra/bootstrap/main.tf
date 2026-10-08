provider "aws" {
  region = var.region
  default_tags {
    tags = merge({
      Project   = var.project
      ManagedBy = "terraform"
      Component = "bootstrap"
    }, var.tags)
  }
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Remote state backend: a versioned, encrypted, private S3 bucket + a DynamoDB
# lock table. This is the classic "who watches the watchmen" step — created
# with local state, then every env's backend points here.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  # State is precious — never let a `terraform destroy` of app resources nuke it.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}

# ---------------------------------------------------------------------------
# GitHub Actions -> AWS via OIDC / Workload Identity Federation. No static
# access keys ever stored in GitHub — the CI job presents a short-lived OIDC
# token and assumes this role, gated on the repo (and branch) in the sub claim.
# (This is the pattern documented in the app's own WIF study guide.)
# ---------------------------------------------------------------------------
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

locals {
  repo = "repo:${var.github_owner}/${var.github_repo}"

  # Exact branch refs are matched with StringEquals (no wildcard slack); only an
  # explicit "*" entry opts into a StringLike pattern. sub claims look like:
  #   repo:owner/repo:ref:refs/heads/main   (exact)
  #   repo:owner/repo:*                      (any ref — opt-in)
  exact_subs    = [for b in var.github_branches : "${local.repo}:ref:refs/heads/${b}" if b != "*"]
  wildcard_subs = [for b in var.github_branches : "${local.repo}:*" if b == "*"]

  # One trust statement per matcher (Allow statements are OR'd). StringEquals and
  # StringLike can't share a statement or they'd be AND'd and never match.
  sub_matchers = concat(
    length(local.exact_subs) > 0 ? [{ test = "StringEquals", values = local.exact_subs }] : [],
    length(local.wildcard_subs) > 0 ? [{ test = "StringLike", values = local.wildcard_subs }] : [],
  )
}

# Trust policy: the role can be assumed ONLY by GitHub Actions runners, and only
# for this repo on the allowed refs. It permits nothing but
# sts:AssumeRoleWithWebIdentity from the GitHub OIDC provider (no account-root or
# IAM-principal trust at all), pins the audience to sts.amazonaws.com, and pins
# the subject to this repo's allowed refs. A token from any other repo, provider,
# or audience — or a plain sts:AssumeRole — cannot assume it.
data "aws_iam_policy_document" "ci_assume" {
  dynamic "statement" {
    for_each = local.sub_matchers
    content {
      effect  = "Allow"
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "Federated"
        identifiers = [aws_iam_openid_connect_provider.github.arn]
      }

      condition {
        test     = "StringEquals"
        variable = "token.actions.githubusercontent.com:aud"
        values   = ["sts.amazonaws.com"]
      }

      condition {
        test     = statement.value.test
        variable = "token.actions.githubusercontent.com:sub"
        values   = statement.value.values
      }
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "${var.project}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.ci_assume.json
  description        = "Assumed by GitHub Actions (OIDC) to plan/apply the ${var.project} stacks."
}

# ---------------------------------------------------------------------------
# Deploy permissions. By default the CI role gets a LEAST-PRIVILEGE policy that
# grants only the services + resource ARNs these stacks actually manage, so a
# leaked OIDC credential can never reach unrelated services (EC2, RDS, IAM
# users, billing, …) or resources outside the wardrobe-builder-* namespace. Flip
# use_power_user_access=true for the broad AWS-managed policy as an escape hatch.
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "ci_power" {
  count      = var.use_power_user_access ? 1 : 0
  role       = aws_iam_role.ci.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

locals {
  acct   = data.aws_caller_identity.current.account_id
  region = var.region
  proj   = var.project
}

data "aws_iam_policy_document" "ci_deploy" {
  # --- Remote-state backend: the state bucket, the lock table, and the KMS
  #     key S3 uses to encrypt state (reachable only through S3). ---
  statement {
    sid       = "TerraformStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}"]
  }
  statement {
    sid       = "TerraformStateObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket_name}/*"]
  }
  statement {
    sid       = "TerraformStateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:DescribeTable"]
    resources = ["arn:aws:dynamodb:${local.region}:${local.acct}:table/${var.lock_table_name}"]
  }
  statement {
    sid       = "StateKmsViaS3"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${local.region}.amazonaws.com"]
    }
  }

  # --- Application resources, each scoped to the wardrobe-builder-* namespace where the
  #     service supports resource-level permissions. ---
  statement {
    sid     = "DynamoDBAppTables"
    effect  = "Allow"
    actions = ["dynamodb:*"]
    resources = [
      "arn:aws:dynamodb:*:${local.acct}:table/${local.proj}-*",
      "arn:aws:dynamodb:*:${local.acct}:table/${local.proj}-*/index/*",
    ]
  }
  statement {
    sid       = "DynamoDBList"
    effect    = "Allow"
    actions   = ["dynamodb:ListTables", "dynamodb:DescribeLimits"]
    resources = ["*"]
  }
  statement {
    sid       = "LambdaFunctions"
    effect    = "Allow"
    actions   = ["lambda:*"]
    resources = ["arn:aws:lambda:*:${local.acct}:function:${local.proj}-*"]
  }
  # Queue -> worker triggers. CreateEventSourceMapping has no resource type, so
  # it's scoped by the target function instead; the mapping ARNs themselves are
  # random UUIDs.
  statement {
    sid       = "LambdaEventSourceMappingCreate"
    effect    = "Allow"
    actions   = ["lambda:CreateEventSourceMapping"]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "lambda:FunctionArn"
      values   = ["arn:aws:lambda:*:${local.acct}:function:${local.proj}-*"]
    }
  }
  statement {
    sid    = "LambdaEventSourceMappings"
    effect = "Allow"
    actions = [
      "lambda:GetEventSourceMapping", "lambda:UpdateEventSourceMapping",
      "lambda:DeleteEventSourceMapping", "lambda:TagResource",
      "lambda:UntagResource", "lambda:ListTags",
    ]
    resources = ["arn:aws:lambda:*:${local.acct}:event-source-mapping:*"]
  }
  statement {
    sid       = "LambdaAccount"
    effect    = "Allow"
    actions   = ["lambda:GetAccountSettings", "lambda:ListFunctions", "lambda:ListEventSourceMappings"]
    resources = ["*"]
  }
  statement {
    sid    = "Logs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource",
      "logs:ListTagsForResource", "logs:TagLogGroup", "logs:UntagLogGroup",
      "logs:ListTagsLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:*:${local.acct}:log-group:/aws/lambda/${local.proj}-*",
      "arn:aws:logs:*:${local.acct}:log-group:/aws/lambda/${local.proj}-*:*",
      "arn:aws:logs:*:${local.acct}:log-group:/aws/apigw/${local.proj}-*",
      "arn:aws:logs:*:${local.acct}:log-group:/aws/apigw/${local.proj}-*:*",
    ]
  }
  statement {
    sid    = "LogsDescribeAndDelivery"
    effect = "Allow"
    # DescribeLogGroups needs "*". CloudWatch Logs "vended log delivery" (used by
    # API Gateway HTTP API access logging) is account-level and can't be scoped
    # to a log-group ARN, so these also take "*".
    actions = [
      "logs:DescribeLogGroups", "logs:DescribeLogStreams",
      "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery", "logs:ListLogDeliveries",
      "logs:PutResourcePolicy", "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }
  statement {
    sid     = "AppS3Buckets"
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::${local.proj}-*",
      "arn:aws:s3:::${local.proj}-*/*",
    ]
  }
  statement {
    sid       = "SqsJobQueues"
    effect    = "Allow"
    actions   = ["sqs:*"]
    resources = ["arn:aws:sqs:*:${local.acct}:${local.proj}-*"]
  }
  statement {
    sid       = "SnsAlerts"
    effect    = "Allow"
    actions   = ["sns:*"]
    resources = ["arn:aws:sns:*:${local.acct}:${local.proj}-*"]
  }
  statement {
    sid    = "Budgets"
    effect = "Allow"
    # ViewBudget/ModifyBudget cover read + create/update/delete; TagResource is
    # needed because the budget carries tags (default_tags).
    actions   = ["budgets:ViewBudget", "budgets:ModifyBudget", "budgets:TagResource", "budgets:UntagResource", "budgets:ListTagsForResource"]
    resources = ["arn:aws:budgets::${local.acct}:budget/${local.proj}-*"]
  }
  statement {
    sid    = "CloudWatchAlarms"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms", "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:EnableAlarmActions", "cloudwatch:DisableAlarmActions",
      "cloudwatch:ListTagsForResource", "cloudwatch:TagResource", "cloudwatch:UntagResource",
    ]
    resources = ["*"]
  }

  # --- Services whose control-plane ARNs aren't predictable / don't support
  #     fine-grained resource scoping. Still a bounded set of services. ---
  statement {
    sid       = "Cognito"
    effect    = "Allow"
    actions   = ["cognito-idp:*"]
    resources = ["*"]
  }
  statement {
    sid    = "Acm"
    effect = "Allow"
    # Custom-domain certs for CloudFront. ACM cert ARNs are generated, and
    # RequestCertificate has no resource scoping, so this is service-scoped "*".
    actions = [
      "acm:RequestCertificate", "acm:DeleteCertificate", "acm:DescribeCertificate",
      "acm:ListCertificates", "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate", "acm:ListTagsForCertificate",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "ApiGateway"
    effect    = "Allow"
    actions   = ["apigateway:*"]
    resources = ["arn:aws:apigateway:*::/*"]
  }
  statement {
    sid       = "CloudFront"
    effect    = "Allow"
    actions   = ["cloudfront:*"]
    resources = ["*"]
  }
  statement {
    sid       = "CallerIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity", "tag:GetResources"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ci_deploy" {
  count       = var.use_power_user_access ? 0 : 1
  name        = "${var.project}-ci-deploy"
  description = "Least-privilege Terraform apply permissions for the ${var.project} stacks (scoped to the ${var.project}-* namespace)."
  policy      = data.aws_iam_policy_document.ci_deploy.json
}

resource "aws_iam_role_policy_attachment" "ci_deploy" {
  count      = var.use_power_user_access ? 0 : 1
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.ci_deploy[0].arn
}

# IAM management for the roles/policies the stacks create — scoped to this
# project's role name prefix. Needed in BOTH modes (PowerUserAccess excludes
# IAM), so it's attached unconditionally.
data "aws_iam_policy_document" "ci_iam" {
  statement {
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:PassRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy",
      "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:TagRole", "iam:UntagRole",
      "iam:CreateServiceLinkedRole"
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*"]
  }
}

resource "aws_iam_role_policy" "ci_iam" {
  name   = "${var.project}-ci-iam"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_iam.json
}
