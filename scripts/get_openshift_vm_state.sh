echo "Getting outputs from OpenShift VM"
export VM_NAME="$1"
export NAMESPACE="$2"
echo $(kubectl wait vm/$VM_NAME -n $NAMESPACE --for=condition=Ready --timeout=400s)
vm_json=$(kubectl get vm $VM_NAME -n $NAMESPACE -o json)
export vm_name="$(echo "$vm_json" | jq -r '.metadata.name')"
export storage="$vm_json" | jq -r '.spec.dataVolumeTemplates[]? | "- \(.metadata.name): size=\(.spec.persistentVolumeClaim.resources.requests.storage)"'
export ip=$(kubectl get vmi $VM_NAME -n $NAMESPACE -o json   | jq -r ' .status.interfaces[]?.ipAddress // "N/A"'   | sed '/^N\/A$/d')
secret_name=$(echo "$vm_json" \
  | jq -r '.spec.template.spec.domain.devices.cloudInitNoCloud.userDataSecretRef.name // ""')
if [[ -n "$secret_name" ]]; then
  echo "Credentials (from secret ${secret_name}):"
  secret_json=$(kubectl get secret ${secret_name} -n $NAMESPACE -o json)
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
  export password=""
fi