/**
 * Copyright 2026 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

locals {
  _pab_policies_factory_path = pathexpand(coalesce(var.factories_config.pab_policies, "-"))
  _pab_policies_factory_data = {
    for f in try(fileset(local._pab_policies_factory_path, "*.yaml"), []) :
    replace(f, ".yaml", "") => yamldecode(templatefile("${local._pab_policies_factory_path}/${f}", var.context))
  }
  pab_policies = merge(
    local._pab_policies_factory_data,
    var.pab_policies
  )
  _pab_policy_bindings_factory_path = pathexpand(coalesce(var.factories_config.pab_policy_bindings, "-"))
  _pab_policy_bindings_factory_data = {
    for f in try(fileset(local._pab_policy_bindings_factory_path, "*.yaml"), []) :
    replace(f, ".yaml", "") => yamldecode(templatefile("${local._pab_policy_bindings_factory_path}/${f}", var.context))
  }
  pab_policy_bindings = merge(
    local._pab_policy_bindings_factory_data,
    var.pab_policy_bindings
  )
}

resource "google_iam_principal_access_boundary_policy" "pab_policies" {
  provider                            = google-beta
  for_each                            = local.pab_policies
  organization                        = local.organization_id_numeric
  location                            = "global"
  display_name                        = each.value.display_name
  principal_access_boundary_policy_id = each.key

  details {
    enforcement_version = coalesce(each.value.enforcement_version, "latest")
    dynamic "rules" {
      for_each = each.value.rules
      content {
        description = rules.value.description
        effect      = coalesce(rules.value.effect, "ALLOW")
        resources   = rules.value.resources
      }
    }
  }
}

# Principal Access Boundary policies take a few seconds to propagate
resource "time_sleep" "pab_propagation" {
  count           = length(google_iam_principal_access_boundary_policy.pab_policies) > 0 ? 1 : 0
  create_duration = "60s"
  depends_on      = [google_iam_principal_access_boundary_policy.pab_policies]
}

resource "google_iam_organizations_policy_binding" "pab_bindings" {
  provider          = google-beta
  for_each          = local.pab_policy_bindings
  organization      = local.organization_id_numeric
  location          = "global"
  policy_kind       = "PRINCIPAL_ACCESS_BOUNDARY"
  policy_binding_id = each.key
  policy = (
    contains(keys(google_iam_principal_access_boundary_policy.pab_policies), each.value.policy_id)
    ? google_iam_principal_access_boundary_policy.pab_policies[each.value.policy_id].id
    : each.value.policy_id
  )
  target {
    principal_set = coalesce(
      each.value.principal_set,
      "//cloudresourcemanager.googleapis.com/organizations/${local.organization_id_numeric}"
    )
  }
  depends_on = [time_sleep.pab_propagation]
}
