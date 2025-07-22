echo "Getting External IP from service"
sleep 60s
set -euo pipefail

VM_NAME="$1"
NAMESPACE="$2"


echo $(kubectl wait vmi/"${VM_NAME}" -n "${NAMESPACE}" --for=condition=Ready --timeout=400s)

# 1. Fetch VM JSON
vm_json=$(kubectl get vm "${VM_NAME}" -n "${NAMESPACE}" -o json)

# 2. VM Name (just echoes back)
export vm_name="$(echo "$vm_json" | jq -r '.metadata.name')"

# 3. Attached Storage (via DataVolumeTemplates)
export storage="$vm_json" | jq -r '
  .spec.dataVolumeTemplates[]? |
  "- \(.metadata.name): size=\(.spec.persistentVolumeClaim.resources.requests.storage)"
'

# 4. IP Addresses (from the corresponding VMI)
export ip=$(kubectl get vmi "${VM_NAME}" -n "${NAMESPACE}" -o json   | jq -r '
      .status.interfaces[]?.ipAddress // "N/A"
    '   | sed '/^N\/A$/d')

# 5. Credentials (if using CloudInit secret)
secret_name=$(echo "$vm_json" \
  | jq -r '.spec.template.spec.domain.devices.cloudInitNoCloud.userDataSecretRef.name // ""')

if [[ -n "$secret_name" ]]; then
  echo "Credentials (from secret ${secret_name}):"
  secret_json=$(kubectl get secret "${secret_name}" -n "${NAMESPACE}" -o json)

  username=$(echo "$secret_json" \
    | jq -r '.data.username' \
    | base64 --decode)
  password=$(echo "$secret_json" \
    | jq -r '.data.password' \
    | base64 --decode)

  export user=$username
  export password=$password
else
  export user=""
  export user=""
fi