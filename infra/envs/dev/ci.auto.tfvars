# Committed, non-secret shared config for dev. Auto-loaded by Terraform on every
# run (local + CI), so local applies and CI applies use the SAME config — no
# drift, no clobber. Sensitive values (your email → alert_email / allowed_emails)
# are NOT here: CI injects them from the ALERT_EMAIL repo Variable via -var;
# locally, put them in a gitignored secret.auto.tfvars.
region             = "us-east-1"
app_origins        = ["http://localhost:8099"]
auth_callback_urls = ["http://localhost:8099/"]
enable_frontend    = true
budget_limit_usd   = 5
allowed_subs       = []
# The CloudFront URL is appended to app_origins / auth_callback_urls
# automatically by the app-stack once enable_frontend creates the distribution.
