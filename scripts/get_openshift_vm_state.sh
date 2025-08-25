echo "Getting outputs from OpenShift VM"
export VM_NAME=$2
export NAMESPACE=$1
export VM_JSON_INPUT=$3
export UUID=$3
echo "VM_NAME=$VM_NAME"
echo "NAMESPACE=$NAMESPACE"
echo "VM_JSON_INPUT=$VM_JSON_INPUT"
echo "UUID=$UUID"

# If VM_JSON_INPUT contains a vmName key, override VM_NAME with it
if [[ -n "$VM_JSON_INPUT" ]]; then
  if echo "$VM_JSON_INPUT" | jq -e . >/dev/null 2>&1; then
    override_name=$(echo "$VM_JSON_INPUT" | jq -r '.vmName // empty')
    if [[ -n "$override_name" && "$override_name" != "null" ]]; then
      export VM_NAME="$override_name"
      echo "VM_NAME overridden from VM_JSON_INPUT.vmName: $VM_NAME"
    fi
  fi
fi

# If UUID is not set (or was set to the raw JSON), try to take it from VM_JSON_INPUT and append to VM_NAME
if [[ -z "$UUID" || "$UUID" == "$VM_JSON_INPUT" ]]; then
  if [[ -n "$VM_JSON_INPUT" ]] && echo "$VM_JSON_INPUT" | jq -e . >/dev/null 2>&1; then
    parsed_uuid=$(echo "$VM_JSON_INPUT" | jq -r '.uuid // empty')
    if [[ -n "$parsed_uuid" && "$parsed_uuid" != "null" ]]; then
      export UUID="$parsed_uuid"
    fi
  fi
fi

# Concatenate VM_NAME with "-UUID" if UUID is available and not already suffixed
if [[ -n "$UUID" ]]; then
  if [[ "$VM_NAME" != *"-$UUID" ]]; then
    export VM_NAME="${VM_NAME}-${UUID}"
    echo "VM_NAME suffixed with UUID: $VM_NAME"
  fi
fi

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