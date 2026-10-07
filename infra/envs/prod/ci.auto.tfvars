# Committed, non-secret shared config for prod. Auto-loaded by Terraform.
# Sensitive values (email → alert_email / allowed_emails) are injected by CI
# from the ALERT_EMAIL repo Variable; locally use a gitignored secret.auto.tfvars.
region             = "us-east-1"
app_origins        = []
auth_callback_urls = []
enable_frontend    = true
budget_limit_usd   = 15
allowed_subs       = []
# Custom domain (e.g. "wardrobe.aniruddhatambe.dev"). Empty = none. Setting this requests an ACM cert on the next apply; flip
# custom_domain_ready to true only AFTER the cert's DNS validation record is
# added at Namecheap and the cert shows ISSUED.
custom_domain       = ""
custom_domain_ready = false
# The CloudFront URL is appended to app_origins / auth_callback_urls
# automatically by the app-stack once enable_frontend creates the distribution.
