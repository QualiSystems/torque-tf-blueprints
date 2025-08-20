import argparse
import json
import os
import sys
import time
from urllib.parse import urlparse
import yaml
import base64
import zlib
from github import Github
from github import Auth
from dataclasses import dataclass
from typing import Any, Dict, Optional, List
from pytorque import TorqueClient, TorqueConfig


@dataclass
class Config:
    token: str
    git_token: str
    github_repo: str
    space: str
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
        help="JSON string representing the workflow/environment (must include id)",
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

    # Parse workflow contract JSON if provided
    try:
        request_obj = json.loads(args.workflow_contract) if args.workflow_contract else {}
    except json.JSONDecodeError as e:
        sys.exit(f"Invalid JSON for --workflow-contract: {e}")

    # Merge precedence layers
    torque_token = (
        args.torque_token
        or os.environ.get("TORQUE_API_TOKEN")
        or request_obj.get("torque_token")
    )
    git_token = (
        args.git_token
        or os.environ.get("GITHUB_TOKEN")
        or request_obj.get("git_token")
    )
    github_repo = (
        args.github_repo
        or os.environ.get("GITHUB_REPO")
        or request_obj.get("github_repo")
    )
    space = args.space or request_obj.get("space") or "Openshift"

    env_id = request_obj.get("id") if isinstance(request_obj, dict) else None
    if not env_id:
        env_id = "K7hLJdYVlfWv"  # for debug purposes.
        # sys.exit("Environment id missing (provide via --workflow-contract JSON using key 'id')")

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
        github_repo=github_repo,
        request=request_obj,
        environment_id=env_id,
        verify_tls=args.verify_tls,
    )


def build_resource_payload(cfg: Config, yaml_url: str, env_data, resource_name: str, timestamp: str) -> Dict[str, Any]:
    # Prepare the payload for the custom resource
    env_details = env_data.get("details", {})
    blueprint_display_name = env_details.get("definition", {}).get("metadata", {}).get("blueprint_display_name", "unknown")
    blueprint = env_details.get("definition", {}).get("metadata", {}).get("blueprint_name", "unknown")
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
            # {
            #     "name": "created_at",
            #     "value": timestamp,
            # },
            {
                "name": "owner_email",
                "value": env_data.get("initiator", {}).get("email", "unknown"),
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


def get_resource_name(env_data, timestamp) -> str:
    # Use environment ID as resource name, or generate a unique one if not provided
    env_name = env_data.get('details', {}).get('definition', {}).get('metadata', {}).get('name', 'unknown')
    return f"env-{env_name.replace(' ', '-')}-{timestamp}"


def modify_yaml(env_yaml) -> str:
    # Modify the environment YAML as needed
    modified_yaml = env_yaml
    modified_yaml.
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
    g = Github(auth=Auth.Token(cfg.git_token))
    print(f"Saving environment YAML to GitHub repository {cfg.github_repo}")
    git_org, git_repo = _parse_repo(cfg.github_repo)
    repo = g.get_repo(f"{git_org}/{git_repo}")
    rel_path = f"saved_environments/{cfg.environment_id}-{timestamp}.yaml"

    # Convert env_yaml to YAML text
    if isinstance(env_yaml, str):
        yaml_text = env_yaml
    else:  # assume dict-like
        yaml_text = yaml.safe_dump(env_yaml, sort_keys=False)

    message = f"Save environment {cfg.environment_id} snapshot at {timestamp}"
    try:
        # If file exists, update; else create
        try:
            existing_obj = repo.get_contents(rel_path)
            # get_contents may return a single ContentFile or a list
            if isinstance(existing_obj, list):
                # find exact match
                match = next((c for c in existing_obj if getattr(c, 'path', None) == rel_path), None)
            else:
                match = existing_obj
            if match and getattr(match, 'sha', None):
                repo.update_file(rel_path, message, yaml_text, match.sha)
                action = "updated"
            else:
                raise FileNotFoundError
        except Exception:
            repo.create_file(rel_path, message, yaml_text)
            action = "created"
        print(f"Environment YAML {action}: {repo.full_name}/{rel_path}")
    except Exception as e:
        print(f"Failed to save environment YAML to GitHub: {e}", file=sys.stderr)
        raise

    # Construct raw URL (works for public or private with auth)
    raw_url = f"https://raw.githubusercontent.com/{git_org}/{git_repo}/main/{rel_path}"
    return raw_url


def main():
    cfg = parse_args()
    # TorqueConfig might not support verify flag directly; client should handle it internally.
    config = TorqueConfig(api_token=cfg.token, base_url=cfg.torque_url)
    with TorqueClient(config) as torque_client:
        timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ")
        env_yaml = torque_client.get_spaces_by_space_name_environments_by_environment_id_eac(
            space_name=cfg.space, environment_id=cfg.environment_id
        )
        env_yaml = modify_yaml(env_yaml)
        env_data = torque_client.get_spaces_by_space_name_environments_by_environment_id(cfg.space, cfg.environment_id)
        resource_name = get_resource_name(env_data, timestamp)
        yaml_url = save_yaml_to_github(cfg, env_yaml, timestamp)
        payload = build_resource_payload(cfg, yaml_url, env_data, resource_name, timestamp)
        resp = torque_client.post_custom_resource(payload)
        try:
            data = resp.json()
        except Exception:
            data = {"raw": resp.text}
        
        print("Success: resource stored/updated")
        print(json.dumps(data, indent=2))
        curl_payload = json.dumps(payload).replace('"', '\\"')
        print(f"To update the resource manually, use:\ncurl -X POST {cfg.torque_url}/api/custom_resource -H 'Authorization: Bearer Token' -H 'Content-Type: application/json' --data \"{curl_payload}\"")


if __name__ == "__main__":
    main()
