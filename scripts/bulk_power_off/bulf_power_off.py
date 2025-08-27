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
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

from pytorque import TorqueClient  # pip install pytorque
import httpx
from dotenv import load_dotenv


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


def execute_workflow(
    client: TorqueClient,
    env_id: str,
    workflow_name: str,
    space: Optional[str] = None,
    payload: Optional[Dict[str, Any]] = None,
    base_url_override: Optional[str] = None,
    timeout: int = 60,
):
    """Execute a Torque workflow against an environment.

    Tries to use a generic HTTP method on TorqueClient if available; otherwise
    falls back to a direct httpx call using client's base_url and token.
    """
    # # Pull connection details from client / env
    # base_url = (
    #     base_url_override
    #     or getattr(client, "base_url", None)
    #     or os.getenv("TORQUE_BASE_URL")
    #     or "https://portal.qtorque.io"
    # )
    # api_token = getattr(client, "api_token", None) or os.getenv("TORQUE_API_TOKEN")
    # if not api_token:
    #     raise RuntimeError("Missing TORQUE_API_TOKEN for authentication.")

    # path = WORKFLOW_EXECUTE_PATH.format(
    #     space=(space or "default"),
    #     env_id=env_id,
    #     workflow=workflow_name,
    # )
    # url = f"{base_url.rstrip('/')}{path}"
    # json_payload = payload or {}

    # # First, try to use a high-level request helper if the client exposes one
    # # (this keeps auth/session behavior consistent with the library).
    # for attr in ("request", "_request", "http_request"):
    #     if hasattr(client, attr):
    #         req_fn = getattr(client, attr)
    #         try:
    #             return req_fn("POST", path, json=json_payload, timeout=timeout)
    #         except TypeError:
    #             # Some clients expect full URL
    #             try:
    #                 return req_fn("POST", url, json=json_payload, timeout=timeout)
    #             except Exception:
    #                 pass
    #         except Exception:
    #             # Fall through to raw httpx
    #             pass

    # # Raw httpx fallback using the token
    # headers = {
    #     "Authorization": f"Bearer {api_token}",
    #     "Accept": "application/json",
    #     "Content-Type": "application/json",
    # }
    # with httpx.Client(timeout=timeout) as s:
    #     resp = s.post(url, headers=headers, json=json_payload)
    # return resp


def parse_env_file(path: Path) -> EnvironmentEnvelope:
    data = json.loads(Path(path).read_text())
    return EnvironmentEnvelope.from_dict(data)


def main():
    load_dotenv()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--env-file", 
        default=os.environ.get("CONTRACT_FILE_PATH"),
        help="Path to ENV.json"
        )
    ap.add_argument("--workflow", default="Power Off", help="Workflow name to run")
    ap.add_argument("--space", default="OpenShift", help="Torque space / namespace for the environment")
    args = ap.parse_args()
    contract = args.env_file
    if not contract:
        contract = os.environ.get("CONTRACT_FILE_PATH")
    env = parse_env_file(Path(contract))
    print(env.summarize())
    print("\n---")

    client = TorqueClient(
        base_url=(args.base_url or os.getenv("TORQUE_BASE_URL") or "https://portal.qtorque.io"),
        api_token=(os.getenv("TORQUE_API_TOKEN") or ""),
    )

    payload = json.loads(args.payload) if args.payload else {}

    print(f"Executing workflow '{args.workflow}' on environment '{env.id}'...")
    resp = execute_workflow(
        client=client,
        env_id=env.id,
        workflow_name=args.workflow,
        space=args.space,
        payload=payload,
        base_url_override=args.base_url,
    )
    print(f"done")



if __name__ == "__main__":
    main()
