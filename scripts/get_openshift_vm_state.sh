echo "Getting outputs from OpenShift VM"
export VM_NAME=$1
export NAMESPACE=$2
echo $(kubectl wait vm/$VM_NAME -n $NAMESPACE --for=condition=Ready --timeout=400s)
export vm_json=$(kubectl get vm $VM_NAME -n $NAMESPACE -o json)
export vm_name="$(echo "$vm_json" | jq -r '.metadata.name')"
export storage="$(echo "$vm_json" | jq -r '.spec.dataVolumeTemplates[]? | "\(.metadata.name) size=\(.spec.storage.resources.requests.storage)"')"
echo "storage=$storage"
echo ip=$(kubectl get vmi $VM_NAME -n $NAMESPACE -o json   | jq -r ' .status.interfaces[]?.ipAddress // "N/A"'   | sed '/^N\/A$/d')
export secret_name=$(echo "$vm_json" \
  | jq -r '.spec.template.spec.volumes[] | select(.name =="cloudinitdisk" ) | .cloudInitNoCloud.userData')
# echo "secret_name=$secret_name"
if [[ -n "$secret_name" ]]; then
  # echo "Credentials (from secret ${secret_name}):"
  export user=$(echo "$vm_json" | jq -r '.spec.template.spec.volumes[] | select(.name == "cloudinitdisk") | .cloudInitNoCloud.userData' | grep '^user' | awk -F': ' '{print $2}')
  export password=$(echo "$vm_json" | jq -r '.spec.template.spec.volumes[] | select(.name == "cloudinitdisk") | .cloudInitNoCloud.userData' | grep '^password:' | awk -F': ' '{print $2}')
else
  export user=""
  export password=""
fi
echo "user=$user"
echo "password=$password" 