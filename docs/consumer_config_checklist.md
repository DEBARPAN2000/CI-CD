# Consumer Repository Configuration Checklist

## Pre-Onboarding (Org-Level Setup)
These must be configured once per organization by the CI/CD template maintainer.

### GitHub Organization Setup
- [ ] Create/enable GHCR token or use GitHub token with `packages:write` permissions
- [ ] Create environment secrets at org level:
  - [ ] `REGISTRY_USERNAME` (if not using GITHUB_TOKEN)
  - [ ] `REGISTRY_PASSWORD` (if not using GITHUB_TOKEN)
  - [ ] `SONARQUBE_HOST_URL`
  - [ ] `SONARQUBE_TOKEN`
- [ ] Create GitHub App or Personal Access Token for version-bump PR automation
  - [ ] Token needs: `contents:write`, `pull-requests:write`
  - [ ] Store as org secret: `AUTOMATION_TOKEN`
- [ ] Set up branch protection on `main`:
  - [ ] Require pull request reviews (1+ reviewer)
  - [ ] Require status checks to pass (CI, SonarQube, etc.)
  - [ ] Require branches to be up to date before merging
  - [ ] Enforce admins
- [ ] Set up staging and production environments:
  - [ ] Define approval required for production deployment
  - [ ] Add required reviewers (if applicable)

### Infrastructure & External Services
- [ ] SonarQube instance access
  - [ ] URL
  - [ ] Authentication token
  - [ ] Project key naming convention
- [ ] Staging environment
  - [ ] Deployment target (K8s cluster, VMs, cloud platform)
  - [ ] Access credentials
  - [ ] Health check endpoints defined
  - [ ] WAF/firewall rules for DAST scanning
- [ ] Production environment
  - [ ] Deployment target
  - [ ] Access credentials
  - [ ] Approval/gating workflow defined
- [ ] Container Registry (if not GHCR)
  - [ ] Registry URL
  - [ ] Credentials
  - [ ] Image retention policies
- [ ] DAST scanning tool setup
  - [ ] OWASP ZAP or equivalent configured
  - [ ] Staging URL whitelisted for scanning
  - [ ] Scan profiles tuned for your stack

---

## Per-Repository Onboarding Checklist

Each consuming repository must complete these steps to use the CI/CD template.

### Step 1: Repository Structure & Project Files
- [ ] Verify project structure is recognized
  - [ ] For .NET:
    - [ ] At least one `.sln` or `.csproj` present
    - [ ] Recommended: `Directory.Build.props` with version property
  - [ ] For Python:
    - [ ] `pyproject.toml` or `setup.py` present
    - [ ] Recommended: version in `pyproject.toml` or `__version__` file
- [ ] Version file configured
  - [ ] Identify canonical version location (single source of truth)
  - [ ] For .NET: `Directory.Build.props` path
  - [ ] For Python: `pyproject.toml` or custom `__version__.py`
  - [ ] Document the path for template config
- [ ] Unit/integration tests configured
  - [ ] Test discovery pattern defined (e.g., `**/*.Tests.csproj`, `tests/test_*.py`)
  - [ ] Test command documented (e.g., `dotnet test`, `pytest`)
  - [ ] Coverage collection configured
- [ ] Linter/formatter configuration present
  - [ ] .NET: `.editorconfig` or `stylecop.json`
  - [ ] Python: `.pylintrc`, `pyproject.toml`, or `setup.cfg`

### Step 2: GitHub Workflows (Caller Setup)
- [ ] Create `.github/workflows/` directory
- [ ] Create `call-ci.yml` (calls reusable CI workflow)
  ```yaml
  name: CI
  on:
    pull_request:
      branches: [main]
    push:
      branches: [main]
  jobs:
    call-ci:
      uses: debarpan-bose-chowdhury/CI-CD/.github/workflows/ci.yml@<tag-or-branch>
      with:
        language: auto  # or 'dotnet', 'python'
        sonar-project-key: <your-org>-<repo-name>
      secrets:
        sonarqube-token: ${{ secrets.SONARQUBE_TOKEN }}
  ```
- [ ] Create `call-docker.yml` (calls docker build/push)
  ```yaml
  name: Build & Push Image
  on:
    push:
      branches: [main]
  jobs:
    call-docker:
      uses: debarpan-bose-chowdhury/CI-CD/.github/workflows/docker-build-push.yml@<tag-or-branch>
      with:
        image-owner: ${{ github.repository_owner }}
        image-name: ${{ github.event.repository.name }}
        registry: ghcr.io
      secrets:
        registry-username: ${{ secrets.REGISTRY_USERNAME }}
        registry-password: ${{ secrets.REGISTRY_PASSWORD }}
  ```
- [ ] (Multi-image repos) Instead of one call per image, pass an `images` JSON array to `docker-build-push.yml`,
      `deploy-*.yml`, `dast-smoke.yml` and `continuous-monitoring.yml`, and use `IMAGE_REF_<NAME>` in your
      compose files. See `examples/multi-image-consumer-workflow.yml` and the README section "Multi-image pipelines".
- [ ] Create `call-deploy-staging.yml`
  ```yaml
  name: Deploy to Staging
  on:
    workflow_run:
      workflows: ["Build & Push Image"]
      types: [completed]
  jobs:
    call-deploy:
      uses: debarpan-bose-chowdhury/CI-CD/.github/workflows/deploy-staging.yml@<tag-or-branch>
      with:
        environment-name: staging
        registry: ghcr.io
        image-owner: ${{ github.repository_owner }}
        image-name: ${{ github.event.repository.name }}
        image-tag: latest
  ```
- [ ] Create `call-dast-smoke.yml`
  ```yaml
  name: DAST & Smoke Tests
  on:
    workflow_run:
      workflows: ["Deploy to Staging"]
      types: [completed]
  jobs:
    call-dast:
      uses: debarpan-bose-chowdhury/CI-CD/.github/workflows/dast-smoke.yml@<tag-or-branch>
      with:
        staging-url: https://staging.example.com
        smoke-test-endpoint: /health
  ```
- [ ] Create `call-deploy-prod.yml`
  ```yaml
  name: Deploy to Production
  on:
    workflow_run:
      workflows: ["DAST & Smoke Tests"]
      types: [completed]
  jobs:
    approval:
      environment: production
      runs-on: ubuntu-latest
      steps:
        - run: echo "Manual approval required before prod deploy"
    call-deploy:
      needs: approval
      uses: debarpan-bose-chowdhury/CI-CD/.github/workflows/deploy-production.yml@<tag-or-branch>
      with:
        environment-name: production
        image-tag: ${{ needs.approval.outputs.approved-tag }}
  ```

### Step 3: Secrets & Environment Variables
- [ ] Create repository secrets (Settings > Secrets and variables > Actions):
  - [ ] `SONARQUBE_TOKEN` (org-level or repo-level override)
  - [ ] `REGISTRY_USERNAME` (if repo-specific credentials)
  - [ ] `REGISTRY_PASSWORD` (if repo-specific credentials)
  - [ ] Any custom secrets required by deployment
- [ ] Create environment variables (Settings > Variables):
  - [ ] `SONARQUBE_PROJECT_KEY`
  - [ ] `REGISTRY_URL` (if not GHCR)
  - [ ] `STAGING_URL`
  - [ ] `PRODUCTION_URL`
  - [ ] `APP_HEALTH_CHECK_ENDPOINT`
- [ ] Create environments (Settings > Environments):
  - [ ] `staging`
    - [ ] Optional: require reviewers
    - [ ] Add deployment branches (e.g., `main`)
  - [ ] `production`
    - [ ] **Require reviewers** (at least 1)
    - [ ] Require manual approval
    - [ ] Add deployment branches (e.g., `main`)
    - [ ] Add protection rules if available

### Step 4: Branch Protection Rules
- [ ] On `main` branch (Settings > Branches > Add rule):
  - [ ] Require status checks to pass:
    - [ ] `CI / build`
    - [ ] `CI / test`
    - [ ] `CI / sonarqube`
    - [ ] `Build & Push Image`
  - [ ] Require pull request reviews before merging
  - [ ] Dismiss stale pull request approvals
  - [ ] Require branches to be up to date before merging
  - [ ] Require merge to be up to date with base branch
  - [ ] Allow force pushes: disabled
  - [ ] Allow deletions: disabled

### Step 5: Versioning Configuration
- [ ] Decide on version file location
  - [ ] .NET: Update `Directory.Build.props` with `<Version>` tag
    ```xml
    <Version>1.0.0</Version>
    ```
  - [ ] Python: Update `pyproject.toml` with `version` field
    ```toml
    [project]
    version = "1.0.0"
    ```
- [ ] Document version path for template:
  - [ ] .NET: `Directory.Build.props`
  - [ ] Python: `pyproject.toml` or custom path
- [ ] Create initial version tag:
  - [ ] `git tag v1.0.0 && git push origin v1.0.0`
  - [ ] This establishes baseline for version bumps

### Step 6: Documentation
- [ ] Create `DEPLOYMENT.md`:
  - [ ] Describe staging and production environment setup
  - [ ] List approval requirements
  - [ ] Document rollback procedure
  - [ ] List health check endpoints
- [ ] Create `TESTING.md`:
  - [ ] Describe unit test setup
  - [ ] Coverage requirements
  - [ ] How to run tests locally
- [ ] Update `README.md`:
  - [ ] Link to CI/CD pipeline status
  - [ ] Link to this template repo
  - [ ] Document version file location

### Step 7: Dry Run & Validation
- [ ] Create feature branch and PR
  - [ ] Verify CI workflow runs
  - [ ] Verify SonarQube gate passes/fails appropriately
  - [ ] Merge to `main`
- [ ] Verify docker build and push workflow
  - [ ] Check image pushed to registry
  - [ ] Verify image tags (version + latest)
  - [ ] Verify SBOM generated
- [ ] Verify staging deployment
  - [ ] Confirm deployment to staging
  - [ ] Test health endpoint
- [ ] Verify DAST and smoke tests
  - [ ] Confirm DAST scan runs
  - [ ] Confirm smoke tests pass
- [ ] Verify approval gate
  - [ ] Confirm production requires manual approval
  - [ ] Test approver can trigger production deploy
- [ ] Verify version bump automation
  - [ ] Merge version-bump PR
  - [ ] Confirm release tag created
  - [ ] Confirm release notes published

### Step 8: Monitoring & Alerts
- [ ] Enable workflow run notifications:
  - [ ] Settings > Notifications
  - [ ] Notify on workflow failures
- [ ] Set up SonarQube alerts (if applicable)
- [ ] Monitor container registry for image scans
- [ ] Set up alert routing for on-call team

---

## Configuration Decision Matrix

| Decision | Options | Recommended | Notes |
|----------|---------|-------------|-------|
| Stack | dotnet / python / auto | auto | Auto-detect unless mixed |
| Registry | GHCR / ACR / ECR / GAR | GHCR | Default for same-org |
| DAST Severity Gate | critical / high+ / medium+ | high+ | Balance speed/security |
| Coverage Minimum | 60% / 70% / 80% | 80% | Adjust per project risk |
| Prod Deployment | auto / manual | manual | Require explicit approval |
| Periodic Scan | daily / weekly / disabled | daily | Scan `latest` + last 10 tags |
| Approval Reviewers | 0 / 1 / 2+ | 2 | Production only, at minimum 1 |

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Workflow not triggered | Caller workflow syntax error | Validate YAML in GitHub editor |
| Build fails on auto-detect | Stack not recognized | Ensure *.sln or pyproject.toml present |
| SonarQube gate fails | Token invalid or project key mismatch | Verify `SONARQUBE_TOKEN` and `sonar-project-key` |
| Docker push fails | Registry credentials invalid | Verify `REGISTRY_USERNAME`, `REGISTRY_PASSWORD` |
| Staging deploy fails | Kubeconfig or deploy credentials missing | Verify environment secrets and `KUBECONFIG` |
| DAST scan skipped | Staging URL unreachable | Verify staging deployment health and WAF rules |
| Version bump PR fails | Version file not found | Verify version file path in configuration |
| Production approval blocked | Not in reviewer list | Add to environment reviewers |
