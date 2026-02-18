---
name: local-ci
description: Test and iterate on GitHub Actions workflows locally using wrkflw, without pushing to GitHub. Validate YAML, run workflows in Docker/Podman/emulation, debug failures, and develop CI pipelines with fast feedback loops. Use when editing .github/workflows/ files or troubleshooting CI.
---

# Local CI Testing with wrkflw

Stop pushing tiny YAML tweaks to GitHub just to see if your workflow passes.
`wrkflw` validates and runs GitHub Actions workflows locally, giving you a fast
feedback loop for CI development.

**Repository:** [bahdotsh/wrkflw](https://github.com/bahdotsh/wrkflw) (MIT, Rust)

## Core Workflow

The typical cycle for iterating on a workflow file:

1. **Validate first** — catch YAML and structural errors with zero overhead:
   ```bash
   wrkflw validate .github/workflows/ci.yml
   ```
   Exit codes: `0` = valid, `1` = validation errors, `2` = usage error. This is
   fast enough for pre-commit hooks.

2. **Run in emulation for fast iteration** — no Docker needed, sandboxed:
   ```bash
   wrkflw run --runtime emulation .github/workflows/ci.yml
   ```
   Watch for "blocked command" warnings — these indicate steps that would work
   on GitHub but are sandboxed in emulation mode.

3. **Run in Docker/Podman for fidelity** — once the logic works, test in a
   container environment closer to GitHub's runners:
   ```bash
   wrkflw run .github/workflows/ci.yml
   wrkflw run --runtime podman .github/workflows/ci.yml
   ```

4. **Debug failures** — preserve containers to inspect state after a failure:
   ```bash
   wrkflw run --preserve-containers-on-failure .github/workflows/ci.yml
   docker exec -it <container-id> bash
   ```

5. **Push to GitHub** only when the workflow passes locally.

## Commands

### Validate

```bash
# Validate all workflows in .github/workflows/
wrkflw validate

# Validate a specific file
wrkflw validate .github/workflows/ci.yml

# Verbose output (shows what's being checked)
wrkflw validate --verbose .github/workflows/ci.yml

# Validate GitLab CI files
wrkflw validate .gitlab-ci.yml --gitlab
```

### Pre-flight: Container Runtime Check

Docker mode (the default) requires the Docker daemon to be running. Before
attempting a Docker-mode run, check:

```bash
docker info > /dev/null 2>&1 && echo "Docker is running" || echo "Docker is NOT running"
```

If Docker isn't running, tell the user and ask them to start it (e.g., launch
Docker Desktop on macOS) before proceeding. Alternatively, suggest using
`--runtime emulation` to skip the container requirement entirely.

For Podman, the equivalent check is:
```bash
podman info > /dev/null 2>&1 && echo "Podman is running" || echo "Podman is NOT running"
```

Emulation mode requires no runtime check.

### Run

```bash
# Run with Docker (default — requires Docker daemon)
wrkflw run .github/workflows/ci.yml

# Run with Podman
wrkflw run --runtime podman .github/workflows/ci.yml

# Run in secure emulation (no container needed)
wrkflw run --runtime emulation .github/workflows/ci.yml

# Verbose output
wrkflw run --verbose .github/workflows/ci.yml

# Preserve failed containers for debugging
wrkflw run --preserve-containers-on-failure .github/workflows/ci.yml
```

### TUI

```bash
# Open the interactive terminal UI (auto-discovers workflows)
wrkflw
# or explicitly:
wrkflw tui
```

The TUI has four tabs: Workflows, Execution, Logs, Help. Key bindings:

| Key | Action |
|-----|--------|
| `Tab` / `1-4` | Switch tabs |
| `j`/`k` or `↑`/`↓` | Navigate |
| `Space` | Toggle workflow selection |
| `Enter` | Run selected / view details |
| `r` | Run all selected workflows |
| `e` | Cycle runtime (Docker → Podman → Emulation) |
| `v` | Toggle Execution / Validation mode |
| `q` | Quit |

### Remote Trigger

For triggering workflows on GitHub (requires `workflow_dispatch:` trigger and
`GITHUB_TOKEN` env var):

```bash
export GITHUB_TOKEN=ghp_your_token

wrkflw trigger workflow-name
wrkflw trigger workflow-name --branch main --input name=Alice --input debug=true
```

## Execution Modes

| Mode | Requires | Fidelity | Speed | Best for |
|------|----------|----------|-------|----------|
| Docker | Docker daemon | High | Slower (image pulls) | Final validation before push |
| Podman | Podman installed | High | Slower | Rootless alternative to Docker |
| Secure Emulation | Nothing | Medium | Fast | Rapid iteration on workflow logic |

**Secure Emulation** runs steps directly on the host in a sandbox. It's the
fastest option and requires no container runtime, but some steps that depend on
the container environment may behave differently. Use it for logic iteration,
then switch to Docker/Podman for fidelity testing.

## Secrets and Environment Variables

GitHub encrypted secrets (`${{ secrets.FOO }}`) are **not supported** locally.
The workaround is to set environment variables with the same names:

```bash
export DEPLOY_TOKEN=test_token_value
export NPM_TOKEN=local_test_value
wrkflw run .github/workflows/deploy.yml
```

Design your workflows to read from env vars that are named the same as your
secrets — this makes them work both on GitHub (where secrets are injected as env
vars) and locally (where you set them directly).

For reusable workflows, pass secrets via explicit mapping in the caller YAML:
```yaml
jobs:
  deploy:
    uses: ./.github/workflows/deploy.yml
    secrets:
      DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
```
The `secrets: inherit` shorthand is not supported.

## What's Supported

- Job dependency resolution (`needs:`) with correct ordering
- Parallel execution of independent jobs
- Matrix builds (keep matrices small for local runs)
- GitHub environment files (`GITHUB_OUTPUT`, `GITHUB_ENV`, `GITHUB_PATH`,
  `GITHUB_STEP_SUMMARY`)
- Standard `GITHUB_*` context variables
- Composite actions (local, remote, and nested)
- JavaScript actions
- Docker container actions (in Docker/Podman modes)
- Local action references (`uses: ./path/to/action`)
- `actions/checkout` (natively handled)
- Reusable workflows with local paths
- Service containers (Docker/Podman modes only)

## What's Not Supported

Know these limitations so you don't waste time debugging something `wrkflw`
can't do:

- **No per-job execution** — you can't run a single job from a workflow; it runs
  all jobs. If you're iterating on one job, consider temporarily commenting out
  others.
- **No GitHub encrypted secrets** — use env vars instead (see above).
- **No artifact upload/download** — `actions/upload-artifact` and
  `actions/download-artifact` don't work locally.
- **No caching** — `actions/cache` doesn't persist between runs.
- **No Windows/macOS runners** — only Linux-based `runs-on` values work.
- **No event trigger simulation** — only `workflow_dispatch` is supported; push,
  pull_request, schedule, etc. are not simulated.
- **No job/step timeouts** — `timeout-minutes:` is ignored.
- **No concurrency controls** — `concurrency:` groups are ignored.
- **No `secrets: inherit`** — use explicit secret mapping.
- **No private repo reusable workflows** — remote `uses:` only works for public
  repos.

## Practical Tips

**Start with validation.** `wrkflw validate` catches most YAML mistakes in
under a second. Run it before attempting execution.

**Use emulation for the edit-run-fix loop.** Docker image pulls add minutes of
latency. Emulation mode gives you sub-second feedback on workflow logic.

**Reduce matrix size for local testing.** A 5×3 matrix that's fine on GitHub's
parallel runners will run sequentially and slowly on your laptop. Temporarily
pare it down while iterating.

**Use local paths for reusable workflows during development.** `uses:
./.github/workflows/shared.yml` resolves locally without network access, so you
can iterate on both the caller and callee simultaneously.

**Check `wrkflw --help` and `wrkflw run --help`** for the full flag surface.
The documentation doesn't exhaustively list all flags; the CLI's own help output
(via `clap`) is the authoritative reference.
