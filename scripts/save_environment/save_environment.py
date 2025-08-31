import argparse
import json
import os
import sys
import time
from urllib.parse import urlparse
import yaml
import base64
import zlib
import requests
from dataclasses import dataclass
from typing import Any, Dict, Optional, List
from pytorque import TorqueClient, TorqueConfig
from pytorque.models.environment import EnvironmentEacSpec, Grain
from pytorque.models.generated import EnvironmentResponse


@dataclass
class Config:
    token: str
    git_token: str
    github_repo: str
    space: str
    saved_artifacts: Dict[str, str]
    environment_id: str
    request: Dict[str, Any]
    torque_url: str = "https://portal.qtorque.io/api"
    timeout: int = 10
    verify_tls: bool = True


def parse_args() -> Config:
    """Parse CLI arguments and environment variables.

    Precedence (highest first):
    1. Explicit CLI values
    2. Environment variables (TORQUE_API_TOKEN, GITHUB_TOKEN, GITHUB_REPO)
    3. Embedded values inside --workflow-contract JSON
    4. Fallback defaults
    """
    p = argparse.ArgumentParser(
        description="Fetch running environment YAML and store as custom resource in Torque inventory"
    )
    p.add_argument("--space", required=False, help="Torque space identifier (default: Openshift)")
    p.add_argument(
        "--workflow-contract",
        required=False,
        type=str,
        default=os.environ.get("CONTRACT_FILE_PATH"),
        help="JSON string representing the workflow/environment (must include id)",
    )
    p.add_argument(
        "--new_inputs",
        required=False,
        default='{"jumpbox-b5e0aa-saved-snap":"my-ns"}',
        type=str,
        help="JSON string representing the new inputs per grain for the environment",
    )
    p.add_argument(
        "--torque-token",
        required=False,
        help="Torque API token (or rely on TORQUE_API_TOKEN env var)",
    )
    p.add_argument(
        "--git-token",
        required=False,
        help="GitHub Personal Access Token (or rely on GITHUB_TOKEN env var)",
    )
    p.add_argument(
        "--github-repo",
        required=False,
        help="GitHub repository target. Accepts 'org/repo' or full https URL (or env GITHUB_REPO)",
    )
    p.add_argument(
        "--verify-tls",
        action="store_true",
        default=True,
        help="Enable TLS verification (default: enabled)",
    )
    args = p.parse_args()

    workflow_contract = args.workflow_contract
    try:
        if os.path.isfile(path=workflow_contract):
            with open(workflow_contract, "r") as f:
                request_obj = json.load(f)
        else:
            request_obj = json.loads(workflow_contract)
    except json.JSONDecodeError as e:
        sys.exit(f"Invalid JSON for --workflow-contract: {e}")
    print(args.new_inputs)
    saved_artifacts = args.new_inputs
    try:
        saved_artifacts_obj = json.loads(saved_artifacts)
    except json.JSONDecodeError as e:
        sys.exit(f"Invalid JSON for --new_inputs: {e}")

    # Merge precedence layers
    torque_token = (
        args.torque_token
        or os.environ.get("TORQUE_API_TOKEN")
    )
    git_token = (
        args.git_token
        or os.environ.get("GITHUB_TOKEN")
    )
    github_repo = (
        args.github_repo
        or os.environ.get("GITHUB_REPO")
    )

    space = args.space or request_obj.get("space") or "Openshift"

    env_id = request_obj.get("id", "") if isinstance(request_obj, dict) else ""

    if not torque_token:
        sys.exit("Torque API token missing (use --torque-token or set TORQUE_API_TOKEN)")
    if not git_token:
        sys.exit("GitHub token missing (use --git-token or set GITHUB_TOKEN)")
    if not github_repo:
        sys.exit("GitHub repo missing (use --github-repo or set GITHUB_REPO, format org/repo)")

    return Config(
        space=space,
        token=torque_token,
        git_token=git_token,
        saved_artifacts=saved_artifacts_obj,
        github_repo=github_repo,
        request=request_obj,
        environment_id=env_id,
        verify_tls=args.verify_tls,
    )


def build_resource_payload(cfg: Config, yaml_url: str, env_data: EnvironmentResponse,
                           saved_artifacts: Dict[str, Any],
                           resource_name: str,
                           timestamp: str) -> Dict[str, Any]:
    # Prepare the payload for the custom resource
    env_details = env_data.details
    blueprint_display_name = env_details.definition.metadata.blueprint_display_name
    blueprint = env_details.definition.metadata.blueprint_name
    payload = {
        "name": resource_name,
        "description": f"Environment {cfg.environment_id} from space {cfg.space}",
        "type": "Environment",
        "location": "openshift-agent",
        "attributes": [
            {
                "name": "environment_yaml",
                "value": yaml_url,
            },
            {
                "name": "space",
                "value": cfg.space,
            },
            {
                "name": "blueprint",
                "value": blueprint,
            },
            {
                "name": "created_at",
                "value": f"{timestamp}",
            },
            {
                "name": "artifacts",
                "value": json.dumps(saved_artifacts),
            },
            {
                "name": "owner_email",
                "value": env_data.initiator.email,
            },
        ],
        "tags": [
            {
                "key": "blueprint",
                "value": blueprint_display_name.replace(" ", "-").lower(),
            }
        ],

    }
    print(f"Payload for resource {resource_name}:\n{json.dumps(payload, indent=2)}")
    return payload


def get_resource_name(env_data: EnvironmentResponse, timestamp) -> str:
    # Use environment ID as resource name, or generate a unique one if not provided
    env_name = env_data.details.definition.metadata.name
    return f"env-{env_name.replace(' ', '-')}-{timestamp}"


def modify_yaml(env_yaml: EnvironmentEacSpec, saved_artifacts: Dict[str, Any]) -> Any:
    # Modify the environment YAML as needed
    modified_yaml = env_yaml
    for key, value in saved_artifacts.items():
        grain_name = key
        grain = modified_yaml.get_grain(grain_name)
        if grain and value:
            # Guard attribute access to avoid issues if API changes
            grain.update_grain_input(new_inputs=value)

    return modified_yaml


def _parse_repo(repo_str: str) -> tuple[str, str]:
    """Return (org, repo) from either org/repo or full https URL."""
    if "://" in repo_str:
        url = urlparse(repo_str)
        parts = [p for p in url.path.split("/") if p]
        if len(parts) < 2:
            raise ValueError("Could not parse organization and repo from URL")
        return parts[0], parts[1]
    # simple org/repo
    if repo_str.count("/") == 1:
        org, repo = repo_str.split("/", 1)
        return org, repo
    raise ValueError("GitHub repository format must be 'org/repo' or full URL")


def save_yaml_to_github(cfg: Config, env_yaml: Any, timestamp: str) -> str:
    """Save the environment YAML to GitHub; create or update the file.

    Returns the raw GitHub URL to the file so that it can be accessed directly.
    """
    print(f"Saving environment YAML to GitHub repository {cfg.github_repo}")
    git_org, git_repo = _parse_repo(cfg.github_repo)
    rel_path = (f"saved_environments/{cfg.environment_id}-"
                f"{timestamp.replace(':', '-')}.yaml")

    # Convert env_yaml to YAML text
    if isinstance(env_yaml, str):
        yaml_text = env_yaml
    else:  # assume dict-like
        yaml_text = yaml.safe_dump(env_yaml)

    # Resolve default branch
    repo_url = f"https://api.github.com/repos/{git_org}/{git_repo}"
    headers = {
        "Authorization": f"token {cfg.git_token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    try:
        repo_resp = requests.get(repo_url, headers=headers, timeout=30, verify=cfg.verify_tls)
        repo_resp.raise_for_status()
        default_branch = repo_resp.json().get("default_branch", "main")
    except Exception as e:
        print(f"Warning: failed to resolve default branch, falling back to 'main': {e}")
        default_branch = "main"

    content_url = f"https://api.github.com/repos/{git_org}/{git_repo}/contents/{rel_path}"

    message = f"Save environment {cfg.environment_id} snapshot at {timestamp}"
    b64_content = base64.b64encode(yaml_text.encode("utf-8")).decode("utf-8")

    # First, check if the file exists to get its SHA (required for update)
    sha: Optional[str] = None
    get_params = {"ref": default_branch}
    get_resp = requests.get(content_url, headers=headers, params=get_params, timeout=30, verify=cfg.verify_tls)
    if get_resp.status_code == 200:
        sha = get_resp.json().get("sha")

    payload: Dict[str, Any] = {
        "message": message,
        "content": b64_content,
        "branch": default_branch,
    }
    if sha:
        payload["sha"] = sha

    put_resp = requests.put(content_url, headers=headers, json=payload, timeout=60, verify=cfg.verify_tls)
    if put_resp.status_code not in (200, 201):
        print(f"GitHub API error: {put_resp.status_code} {put_resp.text}", file=sys.stderr)
        put_resp.raise_for_status()

    action = "updated" if sha else "created"
    print(f"Environment YAML {action}: {git_org}/{git_repo}/{rel_path} on branch {default_branch}")

    # Construct raw URL (works for public repos; private needs auth when fetched)
    raw_url = f"https://raw.githubusercontent.com/{git_org}/{git_repo}/{default_branch}/{rel_path}"
    return raw_url


def convert_saved_artifacts(saved_artifacts: Dict[str, Any], request: Dict[str, Any]) -> Dict[str, str]:
    """Convert saved artifacts from a JSON string to a dictionary."""
    response = {}
    for key in saved_artifacts:
        for value in request.get("resources", []):
            if key.startswith(value.get("resource_name", "")):
                grain = value.get("grain_path")
                if grain:
                    grain_name = grain.split(".")[0]
                    new_inputs = {"json_input": {"volumeSnapshotNamespace":
                                                               saved_artifacts[key], "volumeSnapshot": key}}
                    response[grain_name] = new_inputs
    return response


def main():
    cfg = parse_args()
    # TorqueConfig might not support verify flag directly; client should handle it internally.
    config = TorqueConfig(api_token=cfg.token, base_url=cfg.torque_url)
    with TorqueClient(config) as torque_client:
        timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ")
        env_yaml = torque_client.get_spaces_by_space_name_environments_by_environment_id_eac(
            space_name=cfg.space, environment_id=cfg.environment_id
        )
        saved_artifacts = convert_saved_artifacts(cfg.saved_artifacts, cfg.request)
        env_yaml = modify_yaml(env_yaml, saved_artifacts)
        env_data = torque_client.get_spaces_by_space_name_environments_by_environment_id(cfg.space, cfg.environment_id)
        resource_name = get_resource_name(env_data, timestamp)
        yaml_url = save_yaml_to_github(cfg, env_yaml.to_yaml(), timestamp)
        payload = build_resource_payload(
            cfg, yaml_url, env_data, saved_artifacts, resource_name, timestamp)
        resp = torque_client.post_custom_resource(payload)
        try:
            data = resp.json()
        except Exception:
            data = {"raw": resp.text}
        
        print("Success: Environment Saved")
        print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
