echo "Getting outputs from OpenShift VM"
export VM_NAME=$1
export NAMESPACE=$2
# Retry logic to wait until the VM object exists before waiting for it to become Ready
MAX_RETRIES=${MAX_RETRIES:-30}
SLEEP_BETWEEN=${SLEEP_BETWEEN:-15}

for attempt in $(seq 1 $MAX_RETRIES); do
  if kubectl get vm "$VM_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "VM $VM_NAME found (attempt $attempt/$MAX_RETRIES)"
    break
  fi
  if [[ $attempt -eq $MAX_RETRIES ]]; then
    echo "ERROR: VM $VM_NAME not found after $MAX_RETRIES attempts" >&2
    exit 1
  fi
  echo "VM $VM_NAME not found yet (attempt $attempt/$MAX_RETRIES). Retrying in ${SLEEP_BETWEEN}s..."
  sleep $SLEEP_BETWEEN
done

echo "Waiting for VM $VM_NAME Ready condition (timeout 600s)..."
if ! kubectl wait "vm/$VM_NAME" -n "$NAMESPACE" --for=condition=Ready --timeout=600s; then
  echo "ERROR: VM $VM_NAME did not reach Ready condition within timeout" >&2
  exit 2
fi
export vm_json=$(kubectl get vm $VM_NAME -n $NAMESPACE -o json)
export vm_name="$(echo "$vm_json" | jq -r '.metadata.name')"
export storage="$(echo "$vm_json" | jq -r '.spec.dataVolumeTemplates[]? | "\(.metadata.name) size=\(.spec.storage.resources.requests.storage)"')"
echo "storage=$storage"
export ip=$(kubectl get vmi $VM_NAME -n $NAMESPACE -o json   | jq -r ' .status.interfaces[]?.ipAddress // "N/A"'   | sed '/^N\/A$/d')
echo "ip=$ip"
export secret_name=$(echo "$vm_json" \
  | jq -r '.spec.template.spec.volumes[] | select(.name =="cloudinitdisk" ) | .cloudInitNoCloud.userData')
# echo "secret_name=$secret_name"
if [[ -n "$secret_name" ]]; then
  # echo "Credentials (from secret ${secret_name}):"
  export user=$(echo "$vm_json" | jq -r '.spec.template.spec.volumes[] | select(.name == "cloudinitdisk") | .cloudInitNoCloud.userData' | grep '^user:' | awk -F': ' '{print $2}')
  export password=$(echo "$vm_json" | jq -r '.spec.template.spec.volumes[] | select(.name == "cloudinitdisk") | .cloudInitNoCloud.userData' | grep '^password:' | awk -F': ' '{print $2}')
else
  export user=""
  export password=""
fi
echo "user=$user"
echo "password=$password" 