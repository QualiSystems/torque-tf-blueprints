#!/usr/bin/env bash

# check_saved_pvc_snapshots.sh
# Purpose: Verify that for each provided VM name, the "<vm>-saved" cloned PVC and the
#          corresponding VolumeSnapshot "<vm>-saved-snap" exist and become Ready.
#
# The Helm template (datavolume.yaml) creates for each VM:
#   * PersistentVolumeClaim: <vm>-saved
#   * VolumeSnapshot:        <vm>-saved-snap (source = <vm>-saved PVC)
#
# This script checks their presence & readiness with retries.
#
# Usage:
#   ./check_saved_pvc_snapshots.sh <namespace> <vmNamesCommaSeparated> [timeoutSeconds] [intervalSeconds]
#   If <vmNamesCommaSeparated> is omitted, the script will attempt to extract VM names
#   from the JSON file pointed to by $CONTRACT_FILE_PATH. It looks for all inputs with
#   name == "vm_name" and uses their values.
#
# Environment variable overrides (optional):
#   NAMESPACE, VM_NAMES, TIMEOUT, INTERVAL
#
# Exit Codes:
#   0 - All snapshots ready
#   1 - Missing PVC(s)
#   2 - Missing snapshot(s)
#   3 - Snapshot(s) not ready before timeout
#   4 - Invalid usage
#
# Output:
#   Exports & echoes a line snapshots_json=<json> where <json> is a mapping
#   of "<vm>-saved-snap" : "<namespace>" pairs (for every VM requested),
#   regardless of readiness state (so consuming tools know intended snapshot names).

set -o errexit
set -o nounset
set -o pipefail

print_usage() {
	grep '^#' "$0" | sed 's/^# \{0,1\}//'
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
	print_usage
	exit 0
fi

NAMESPACE=${1:-${NAMESPACE:-}}
RAW_VM_NAMES=${2:-${VM_NAMES:-}}
TIMEOUT=${3:-${TIMEOUT:-300}}
INTERVAL=${4:-${INTERVAL:-10}}

if [[ -z "$RAW_VM_NAMES" ]]; then
	# Try to auto-discover from CONTRACT_FILE_PATH if provided
	if [[ -n "${CONTRACT_FILE_PATH:-}" && -f "${CONTRACT_FILE_PATH}" ]]; then
		# Extract all input values where name == vm_name
		AUTO_VM_NAMES=$(jq -r '.inputs[]? | select(.name=="vm_name") | .value' "${CONTRACT_FILE_PATH}" 2>/dev/null | sed 's/^ *//;s/ *$//') || AUTO_VM_NAMES=""
		if [[ -n "$AUTO_VM_NAMES" ]]; then
			# Join lines with commas
			RAW_VM_NAMES=$(echo "$AUTO_VM_NAMES" | paste -sd, -)
			echo "Discovered VM names from CONTRACT_FILE_PATH: $RAW_VM_NAMES"
		fi
	fi
fi

if [[ -z "$NAMESPACE" || -z "$RAW_VM_NAMES" ]]; then
	echo "ERROR: namespace and vm names are required (provide arg, VM_NAMES env var, or CONTRACT_FILE_PATH JSON with vm_name inputs)" >&2
	print_usage >&2
	exit 4
fi

IFS=',' read -r -a VM_LIST <<< "${RAW_VM_NAMES}"

# Build JSON mapping snapshot_name -> namespace (for all requested VMs)
build_snapshot_json() {
	local first=true
	local json="{"
	for vm in "${VM_LIST[@]}"; do
		vm_trimmed=$(echo "$vm" | xargs)
		[[ -z "$vm_trimmed" ]] && continue
		snap_name="${vm_trimmed}-saved-snap"
		if $first; then
			first=false
		else
			json+=" ,"
		fi
		# namespace value constant per invocation
		json+="\"${snap_name}\":\"${NAMESPACE}\""
	done
	json+="}"
	echo "$json"
}

SNAPSHOTS_JSON=$(build_snapshot_json)
export snapshots_json="${SNAPSHOTS_JSON}"

secs_left=$TIMEOUT
missing_pvcs=()
missing_snaps=()
not_ready_snaps=()

echo "Checking cloned PVCs and VolumeSnapshots in namespace '$NAMESPACE' for VMs: ${VM_LIST[*]}"
echo "Timeout: ${TIMEOUT}s  Interval: ${INTERVAL}s"

all_ready=false
while (( secs_left >= 0 )); do
	missing_pvcs=()
	missing_snaps=()
	not_ready_snaps=()

	for vm in "${VM_LIST[@]}"; do
		vm_trimmed=$(echo "$vm" | xargs) # trim spaces
		[[ -z "$vm_trimmed" ]] && continue
		saved_pvc="${vm_trimmed}-saved"
		snap="${vm_trimmed}-saved-snap"

		# Check PVC exists
		if ! kubectl get pvc "$saved_pvc" -n "$NAMESPACE" >/dev/null 2>&1; then
			missing_pvcs+=("$saved_pvc")
			continue
		fi

		# Check snapshot exists
		if ! kubectl get volumesnapshot.snapshot.storage.k8s.io "$snap" -n "$NAMESPACE" >/dev/null 2>&1; then
			missing_snaps+=("$snap")
			continue
		fi

		# Check snapshot readiness
		ready=$(kubectl get volumesnapshot "$snap" -n "$NAMESPACE" -o json 2>/dev/null | jq -r '.status.readyToUse // false') || ready="false"
		if [[ "$ready" != "true" ]]; then
			not_ready_snaps+=("$snap")
		fi
	done

	if (( ${#missing_pvcs[@]} == 0 && ${#missing_snaps[@]} == 0 && ${#not_ready_snaps[@]} == 0 )); then
		all_ready=true
		break
	fi

	echo "Status:"
	[[ ${#missing_pvcs[@]} > 0 ]] && echo "  Missing PVCs: ${missing_pvcs[*]}"
	[[ ${#missing_snaps[@]} > 0 ]] && echo "  Missing Snapshots: ${missing_snaps[*]}"
	[[ ${#not_ready_snaps[@]} > 0 ]] && echo "  Snapshots not Ready yet: ${not_ready_snaps[*]}"

	if (( secs_left == 0 )); then
		break
	fi

	sleep "$INTERVAL"
	(( secs_left-=INTERVAL )) || true
done

if [[ "$all_ready" == true ]]; then
	echo "All cloned PVCs and snapshots are present and Ready.";
	echo "snapshots_json=${SNAPSHOTS_JSON}"
	exit 0
fi

if (( ${#missing_pvcs[@]} > 0 )); then
	echo "ERROR: Missing PVCs: ${missing_pvcs[*]}" >&2
	echo "snapshots_json=${SNAPSHOTS_JSON}"
	exit 1
fi

if (( ${#missing_snaps[@]} > 0 )); then
	echo "ERROR: Missing VolumeSnapshots: ${missing_snaps[*]}" >&2
	echo "snapshots_json=${SNAPSHOTS_JSON}"
	exit 2
fi

if (( ${#not_ready_snaps[@]} > 0 )); then
	echo "ERROR: VolumeSnapshots not Ready before timeout (${TIMEOUT}s): ${not_ready_snaps[*]}" >&2
	echo "snapshots_json=${SNAPSHOTS_JSON}"
	exit 3
fi

# Fallback (shouldn't reach here)
echo "ERROR: Unknown state" >&2
echo "snapshots_json=${SNAPSHOTS_JSON}"
exit 99

