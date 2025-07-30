output "Scratch_Org_URL" {
  value = local.scratch_org_details.LoginUrl
}

output "Scratch_Org_1_Time_Sign_in_URL" {
  value = local.scratch_org_url.url
}