#!/usr/bin/env python3
"""Parse ENV.json and trigger a Torque workflow using pyTorque.

Usage:
  python run_torque_workflow.py --env-file ENV.json --workflow <WORKFLOW_NAME> [--space <SPACE_NAME>] [--base-url https://portal.qtorque.io]
  
Auth:
  Provide a Torque API token via the TORQUE_API_TOKEN environment variable.
  Optionally set TORQUE_BASE_URL; you can also pass --base-url.

Notes:
  - This script uses the pyTorque client for configuration and HTTP plumbing when available.
  - The exact REST path for executing a workflow may differ by account. If you get a 404,
    adjust the WORKFLOW_EXECUTE_PATH format string below.
"""
from __future__ import annotations

import argparse
import json
import os
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

from pytorque import TorqueClient  # pip install pytorque


@dataclass
class EnvInput:
    name: str
    type: str
    value: Any
    sensitive: bool = False
    description: Optional[str] = None

@dataclass
class Grain:
    kind: str
    path: str
    outputs: Dict[str, Any]

@dataclass
class Resource:
    grain_path: str
    resource_name: str
    resource_type: str
    identifier: str
    attributes: Dict[str, Any]

@dataclass
class EnvironmentEnvelope:
    id: str
    name: str
    owner_email: str
    last_used: str
    inputs: List[EnvInput]
    outputs: Dict[str, Any]
    grains: Dict[str, Grain]
    resources: List[Resource]

    @staticmethod
    def from_dict(d: Dict[str, Any]) -> "EnvironmentEnvelope":
        inputs = [EnvInput(**item) for item in d.get("inputs", [])]
        grains = {
            k: Grain(**v) for k, v in d.get("grains", {}).items()
        }
        resources = [Resource(**r) for r in d.get("resources", [])]
        return EnvironmentEnvelope(
            id=d.get("id", ""),
            name=d.get("name", ""),
            owner_email=d.get("owner_email", ""),
            last_used=d.get("last_used", ""),
            inputs=inputs,
            outputs=d.get("outputs", {}) or {},
            grains=grains,
            resources=resources,
        )

    def summarize(self) -> str:
        lines = [
            f"Environment ID:   {self.id}",
            f"Name:             {self.name}",
            f"Owner:            {self.owner_email}",
            f"Last used:        {self.last_used}",
            "",
            "Inputs:",
        ]
        for i in self.inputs:
            val = "***" if i.sensitive else i.value
            lines.append(f"  - {i.name} ({i.type}): {val}")
        lines.append("")
        lines.append("Outputs (current):")
        if self.outputs:
            for k, v in self.outputs.items():
                lines.append(f"  - {k}: {v}")
        else:
            lines.append("  (none)")
        lines.append("")
        lines.append("Grains:")
        for k, g in self.grains.items():
            lines.append(f"  - {k}: kind={g.kind}, path={g.path}")
        lines.append("")
        lines.append("Resources:")
        for r in self.resources:
            lines.append(f"  - {r.resource_name} [{r.resource_type}] from {r.grain_path}")
        return "\n".join(lines)


def parse_env_file(path: Path) -> EnvironmentEnvelope:
    data = json.loads(Path(path).read_text())
    return EnvironmentEnvelope.from_dict(data)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--space", default="OpenShift", help="Torque space / namespace for the environment")
    ap.add_argument("--workflow", default="openshift-vm-power-off", help="Workflow name to run")
    ap.add_argument("--token", default=os.getenv("TORQUE_API_TOKEN"), help="Optional JSON payload to send to the workflow")
    args = ap.parse_args()
    contract = os.getenv("CONTRACT_FILE_PATH")
    if not contract:
        raise ValueError("Missing --env-file argument or CONTRACT_FILE_PATH env var")
    env = parse_env_file(Path(contract))
    print(env.summarize())
    print("\n---")

    client = TorqueClient(
        api_token=args.token,
    )
    environment_details = client.get_spaces_by_space_name_environments_by_environment_id(space_name=args.space, environment_id=env.id)
    workflow_details = client.get_spaces_by_space_name_catalog_by_blueprint_name(space_name=args.space, blueprint_name=args.workflow)
    for resource in env.resources:
        grain = env.grains.get(resource.grain_path)
        print(f"Found resource: {resource.identifier}")
        payload = {
            "environment_name": f"{args.workflow}-{uuid.uuid4()}",
            "blueprint_name": args.workflow,
            "inputs": {},
            "source": {
                "repository_name": workflow_details.details.repository_name
            },
            "automation": "false",
            "owner_email": env.owner_email,
            "entity_metadata": {
                "type": "env_resource",
                "environment_id": env.id,
                "grain_path": resource.grain_path,
                "resource_id": resource.identifier,
            },
            "env_references_values": {},
            "instantiation_name": f"{args.workflow}-{str(uuid.uuid4())[:8]}"
        }
        print(f"Executing workflow '{args.workflow}' on environment '{env.id}'...")
        response = client.post_spaces_by_space_name_environments(space_name=args.space, body=payload)

    print(f"done")


if __name__ == "__main__":
    main()
