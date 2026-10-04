#!/usr/bin/env python3
"""Deploy pinned applications; keep successful fingerprints outside runner workspaces."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]


def git(directory, *args, capture=True):
    result = subprocess.run(
        ["git", "-C", str(directory), *args], check=True, text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else None


def load_apps(repo):
    apps = json.loads((repo / "apps.json").read_text())
    seen = set()
    for name, spec in apps.items():
        if not name or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-" for c in name):
            raise ValueError(f"Invalid application name: {name}")
        if not set(spec["depends_on"]).issubset(seen):
            raise ValueError(f"Dependencies of {name} must be listed earlier in apps.json")
        if not (repo / "deploy/adapters" / f"{name}.sh").is_file():
            raise ValueError(f"Missing deployment adapter: {name}")
        seen.add(name)
    return apps


def select_apps(apps, selected):
    if selected == "all":
        return set(apps)
    if selected not in apps:
        raise ValueError(f"Unknown application: {selected}")
    # Updating a library also updates all its consumers.
    wanted = {selected}
    for name, spec in apps.items():
        if wanted.intersection(spec["depends_on"]):
            wanted.add(name)
    consumers = wanted.copy()
    for name in reversed(apps):
        if name in wanted:
            wanted.update(apps[name]["depends_on"])
    return wanted, consumers


def fingerprint(repo, name, apps, revisions, config_dir):
    """Only inputs that change what runs for this app: its own pinned revision (the
    submodule commit), its adapter, the shared adapter helpers and its host config.
    Dependencies order and gate deployments but never trigger a redeploy, and neither
    do edits to apps.json or this script."""
    digest = hashlib.sha256()
    digest.update(f"{name}:{revisions[name]}\n".encode())
    paths = [repo / "deploy/adapters/common.sh", repo / f"deploy/adapters/{name}.sh"]
    if name == "obsy":
        paths.append(repo / "deploy/compose/obsy.yml")
    paths.append(config_dir / f"{name}.sh")
    for path in paths:
        digest.update(path.name.encode())
        digest.update(path.read_bytes() if path.exists() else b"<missing>")
    return digest.hexdigest()


def prepare_checkout(source, target, revision):
    """Independent repositories keep Git metadata usable on the host."""
    target.parent.mkdir(parents=True, exist_ok=True)
    if not (target / ".git").exists():
        if target.exists() and any(target.iterdir()):
            raise RuntimeError(f"Refusing to replace a non-Git directory: {target}")
        target.mkdir(exist_ok=True)
        git(target, "init", capture=False)
        git(target, "remote", "add", "origin", git(source, "remote", "get-url", "origin"))
    if git(target, "status", "--porcelain"):
        raise RuntimeError(f"Uncommitted changes at {target}; commit and push or back them up first")
    # Existing folders are often shallow (for example from a `fetch-depth: 1` workflow),
    # and Git cannot move a shallow root forward by fetching from another shallow copy.
    if git(target, "rev-parse", "--is-shallow-repository") == "true":
        git(target, "fetch", "--unshallow", "--no-tags", "origin", capture=False)
    # Transfer the exact checked-out revision, not a branch that can change mid-run.
    git(target, "fetch", "--no-tags", str(source), revision, capture=False)
    has_head = subprocess.run(
        ["git", "-C", str(target), "rev-parse", "--verify", "HEAD"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0
    if has_head:
        current = git(target, "rev-parse", "HEAD")
        if current != revision and subprocess.run(
            ["git", "-C", str(target), "merge-base", "--is-ancestor", current, revision],
        ).returncode != 0:
            raise RuntimeError(f"Local/divergent commits at {target}; refusing to discard them")
    git(target, "checkout", "--detach", revision, capture=False)
    git(target, "submodule", "update", "--init", "--recursive", capture=False)


def deploy(repo, root, state_dir, config_dir, selected="all", force=False, dry_run=False):
    apps = load_apps(repo)
    selection = select_apps(apps, selected)
    wanted, forced = (selection, selection) if selected == "all" else selection
    revisions = {name: git(repo / "apps" / name, "rev-parse", "HEAD") for name in apps}
    state_file = state_dir / "deployed.json"
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    failures = set()
    for name, spec in apps.items():
        if name not in wanted:
            continue
        signature = fingerprint(repo, name, apps, revisions, config_dir)
        previous = state.get(name, {})
        if previous.get("fingerprint") == signature and not (force and name in forced) and (root / name / ".git").exists():
            print(f"{name}: unchanged", flush=True)
            continue
        if failures.intersection(spec["depends_on"]):
            print(f"{name}: skipped because a dependency failed", file=sys.stderr)
            failures.add(name)
            continue
        print(f"{name}: {'would deploy' if dry_run else 'deploying'} {revisions[name]}", flush=True)
        if dry_run:
            continue
        try:
            prepare_checkout(repo / "apps" / name, root / name, revisions[name])
            env = dict(os.environ, APP_NAME=name, APP_DIR=str(root / name),
                       APP_REVISION=revisions[name], ORCHESTRATOR_DIR=str(repo),
                       VPS_APPS_ROOT=str(root), VPS_CONFIG_DIR=str(config_dir))
            subprocess.run(["bash", str(repo / "deploy/adapters" / f"{name}.sh")], env=env, check=True)
            state[name] = {"revision": revisions[name], "fingerprint": signature}
            temporary = state_file.with_suffix(".tmp")
            temporary.write_text(json.dumps(state, indent=2) + "\n")
            os.replace(temporary, state_file)
        except (subprocess.CalledProcessError, RuntimeError, OSError) as error:
            print(f"{name}: deployment failed: {error}", file=sys.stderr, flush=True)
            failures.add(name)
    if failures:
        print("Failed or blocked applications: " + ", ".join(sorted(failures)), file=sys.stderr)
        return 1
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", default="all")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="Print the plan without writing files or running Docker")
    args = parser.parse_args()
    root = Path(os.environ.get("VPS_APPS_ROOT", "/opt/vps-apps/apps")).resolve()
    state_dir = Path(os.environ.get("VPS_STATE_DIR", "/var/lib/vps-apps")).resolve()
    config_dir = Path(os.environ.get("VPS_CONFIG_DIR", "/etc/vps-apps")).resolve()
    try:
        # Protect against accidental checkout/deployment path overlap.
        if root == REPO or root.is_relative_to(REPO) and root != REPO / ".production":
            raise ValueError("VPS_APPS_ROOT must be outside this checkout (or use .production for local testing)")
        if args.dry_run:
            return deploy(REPO, root, state_dir, config_dir, args.app, args.force, True)
        state_dir.mkdir(parents=True, exist_ok=True)
        with (state_dir / "deploy.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            return deploy(REPO, root, state_dir, config_dir, args.app, args.force)
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print(f"Deployment error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
