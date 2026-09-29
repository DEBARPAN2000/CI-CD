# CI/CD Template Repository Design

## Purpose
Provide a reusable GitHub Actions CI/CD template that can be called from other repositories in the same org without copy/paste.

## Scope
- Template repo contains only reusable workflows (`workflow_call`).
- Supports private and public repos in one org.
- Supports .NET and Python repositories through auto-detection.
- Uses trunk-based development:
  - feature branches -> pull request -> `main`
  - automated version-bump PR after merge to `main`
  - release tag created only after the version-bump PR merges

## Core requirements

### 1. Reusable workflow model
Consumers call workflows from this repo instead of keeping full pipeline logic locally.

Recommended structure:
- `.github/workflows/ci.yml`
- `.github/workflows/version-bump.yml`
- `.github/workflows/release-tag.yml`
- `.github/workflows/docker-build-push.yml`
- `.github/workflows/deploy-staging.yml`
- `.github/workflows/dast-smoke.yml`
- `.github/workflows/deploy-production.yml`
- `.github/workflows/continuous-monitoring.yml`
- `.github/workflows/image-periodic-scan.yml`
- `.github/workflows/security.yml` (optional split from CI)
- `docker/Dockerfile.dotnet`
- `docker/Dockerfile.python`

### Multi-image support
The build, deploy, DAST and monitoring workflows accept an optional `images` JSON array (name, language,
dockerfile, context, role `service|batch`, smoke-command, compose-service, health-url, build-args) so one
repository can ship several images, in the same or different languages, through one pipeline. Builds run as a
matrix and share one tag; `service` images deploy together in a single compose stack (compose receives
`IMAGE_REF_<NAME>` per image); `batch` images are built, optionally smoke-run and scanned but not deployed.
Empty `images` keeps the original single-image behaviour. Details: README, "Multi-image pipelines".

Each reusable workflow should accept inputs for:
- repository type
- language override (`dotnet`, `python`, or `auto`)
- paths/globs to detect project files
- test command overrides
- version file paths
- release branch/tag prefix

### 2. Auto-detection
The pipeline should detect the stack from repository contents:
- .NET: `*.sln`, `*.csproj`, `global.json`, `Directory.Build.props`
- Python: `pyproject.toml`, `requirements*.txt`, `setup.py`, `setup.cfg`

If both are present, the workflow should support matrix execution or a caller-controlled override.
If none are found, fail fast with a clear message.

### 3. CI flow
Single CI workflow should cover:
- checkout
- dependency restore
- build
- unit/integration tests
- coverage collection
- issues, security hotspot, and coverage checks through SonarQube
- lint/format checks
- SCA/SAST where available
- SBOM generation
- artifact upload
- fail fast on any mandatory check failure

### 4. Container packaging and registry publish
The template repo should provide common Docker packaging logic so consumer repos do not need to duplicate container build files.

Recommended approach:
- Provide one reusable Dockerfile template for .NET and one for Python.
- Keep both Dockerfiles multi-stage so build dependencies do not reach the runtime image.
- Use a non-root final image.
- Allow the workflow to select the correct Dockerfile automatically from repository detection, with a manual override.
- Default the registry target to GitHub Container Registry for same-org repositories, while still allowing other registries through inputs and secrets.

Docker packaging workflow should:
- build with `docker buildx`
- tag the image with both the version tag and `latest`
- push the image only after successful build/test gates
- expose the final image reference and digest for downstream jobs
- attach/publish SBOM alongside the pushed image

### 5. Release flow
Release is split into two steps:

#### Step A: manual PR merged to `main`
- The workflow reads the merged PR title/body and Conventional Commit summary.
- Version is calculated from the current version plus commit intent:
  - `fix` -> patch
  - `feat` -> minor
  - breaking change -> major
  - default -> patch
- An automated version-bump branch is created.
- An automated PR updates version files only.
- No tag is created yet.

#### Step B: version-bump PR merged
- After the version PR merges, a release workflow creates the git tag.
- Tag is created from the merged version-bump commit on `main`.
- Release notes are published from the merged change set.

### 6. Versioning rules
- Conventional Commits drive the bump.
- Current version is the source of truth.
- Version files should be repository-specific and configurable.

Suggested version sources:
- .NET: `Directory.Build.props`, `src/*/*.csproj`, `version.json`
- Python: `pyproject.toml`, `package/__init__.py`, `__version__` file

### 7. Org-level access
Because this is for repos in one org:
- reusable workflow permissions should assume same-org access
- callers should pin to a tag or SHA
- workflow permissions should be minimal and explicit

Recommended permissions:
- `contents: read` for CI
- `contents: write` only for versioning/tag steps
- `pull-requests: write` for automated PR creation

### 8. End-to-end pipeline stages (as reported from draw.io)
The reusable workflows should implement these stages in this order with explicit gates:

1. **Checkout + trigger policy**
   - checkout private GitHub repository
   - trigger on PR to `main`
   - enforce branch-updated policy before merge (`fail=stop`)

2. **Build, unit/integration test, coverage**
   - compile/build
   - run unit and integration tests
   - collect coverage (`fail=stop`)

3. **SCA + SBOM**
   - dependency/container/package vulnerability checks
   - generate SBOM and persist artifact
   - gate: `fail=stop`, `pass=continue`

4. **Code quality and static security**
   - SonarQube analysis
   - lint checks
   - CodeQL analysis
   - gate: `fail=stop`, `pass=continue`

5. **Package & containerize**
   - build application package
   - build container image from reusable template Dockerfile

6. **Push image + SBOM to registry**
   - push signed/tagged image
   - publish SBOM/provenance linked to the image digest

7. **Deploy to staging**
   - deploy candidate image to staging environment

8. **DAST + smoke checks (mandatory)**
   - run DAST and smoke tests on staging deployment
   - OWASP ZAP for dynamic checks
   - curl/Postman smoke tests
   - gate: `fail=stop`, `pass=continue`

9. **Approval, squash/merge, production deploy**
   - after approval, squash and merge to `main`
   - deploy to production
   - gate: `fail=stop`, `pass=continue`

10. **Continuous monitoring**
    - continuous monitoring + SBOM traceability
    - passive DAST + WAF signals
    - anti-virus/malware monitoring where applicable

### 9. Periodic image re-scan design
In addition to build-time scanning, add a scheduled workflow (`image-periodic-scan.yml`) to continuously scan already-pushed images.

Suggested baseline:
- trigger: `schedule` (daily) + manual dispatch
- scope: scan `latest` and configurable recent tags (for example last 10 release tags)
- sources: registry image and SBOM artifact
- policy:
  - critical/high findings in runtime image -> fail workflow, open/update tracking issue
  - unchanged acknowledged risk -> keep issue open with last-seen timestamp
- outputs:
  - SARIF upload where supported
  - issue/summary report with image digest, package, CVE, severity, fix availability

### 10. Gate alignment model
Every stage must declare:
- **gate owner** (which reusable workflow enforces it)
- **required signal** (test result, scanner status, quality gate, DAST pass)
- **threshold policy** (for example min coverage, max severity)
- **failure action** (`stop`, block merge/deploy, notify)
- **bypass policy** (who can override, evidence required, audit trail)

This avoids misaligned checks where a job runs but does not block risky promotion.

### 11. Design improvement suggestions
1. **Supply chain hardening**: sign images and attest SBOM/provenance (SLSA-style) before deployment. - Approved
2. **Environment protection rules**: require explicit approval for production deploy with protected environment secrets. - Approved
3. **Progressive delivery**: add canary/blue-green option for production rollout. - Rejected
4. **Security triage automation**: automatically create actionable issues for periodic scan findings. - Approved
5. **Policy-as-code**: centralize gate thresholds in one config file to keep behavior consistent across consumer repos. - Approved
6. **Observability contract**: standardize health/readiness endpoints required for smoke checks. - Rejected
7. **Rollback workflow**: add a reusable rollback workflow to redeploy last known-good digest quickly. - Approved

### 12. Ambiguities to clarify before implementation
1. Which DAST findings should block promotion (critical only, high+critical, or all medium+ above)? - Medium+
2. Should periodic image scans block releases, or only create issues/alerts for remediation? - Create issues
3. What minimum coverage threshold should be enforced at gate level? - 85%
4. Is production deployment fully automated after approval, or should there be a manual promotion step? - Automated
5. Which registry should be canonical default (GHCR only, or GHCR + optional ACR/ECR/GAR presets)? - GHCR

## Proposed implementation order

1. Build the reusable CI workflow with auto-detection.
2. Add reusable Dockerfile templates and the docker build/push workflow.
3. Add staging deploy + mandatory DAST/smoke gate workflows.
4. Add periodic image re-scan workflow and reporting.
5. Add version detection and Conventional Commit bump calculation.
6. Add automated version-bump PR creation.
7. Add release-tag workflow that runs only after version PR merge.
8. Add docs showing how consumer repos call the workflows.

## Initial architecture decision
One reusable CI/CD pipeline family, not a copied pipeline per repo.
Consumer repos will only supply a thin caller workflow and minimal repo-specific config.
