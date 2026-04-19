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

resource "google_iam_projects_policy_binding" "pab_bindings" {
  provider          = google-beta
  for_each          = local.pab_policy_bindings
  project           = local.project.project_id
  location          = "global"
  policy_kind       = "PRINCIPAL_ACCESS_BOUNDARY"
  policy_binding_id = each.key
  policy            = each.value.policy_id
  target {
    principal_set = coalesce(
      each.value.principal_set,
      "//cloudresourcemanager.googleapis.com/projects/${local.project.project_id}"
    )
  }
}
