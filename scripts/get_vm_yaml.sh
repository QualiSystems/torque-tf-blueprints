#!/usr/bin/env bash
set -euo pipefail

# Usage: get_vm_yaml.sh "vm1,vm2 vm3" <namespace>
raw_vm_list="${1:-}"
namespace="$2"

if [[ -z "$raw_vm_list" ]]; then
  echo "No VM names supplied (argument 1)."
  exit 1
fi

echo "Getting output from OpenShift VM(s) in namespace: $namespace"

# Split on commas and/or spaces
IFS=', ' read -r -a vm_names <<< "$raw_vm_list"

# Optional accumulator (uncomment if you need it exported)
aggregated=""
for vm in "${vm_names[@]}"; do
  [[ -z "$vm" ]] && continue
  aggregated+="$(kubectl get vm "$vm" -n "$namespace" -o yaml)$'\n---\n'"
done

export VM_YAMLS="$aggregated"
