# CI/CD Template Repository

A reusable, enterprise-grade GitHub Actions CI/CD template for .NET and Python applications. Designed for trunk-based development with full security gates, automated versioning, and release management.

## 🎯 Features

### Core Capabilities
- **Multi-language support**: Auto-detection for .NET and Python projects
- **Reusable workflows**: Use `workflow_call` pattern—no copy/paste needed
- **Security gates**: SCA → SBOM → CodeQL → DAST → Production
- **Automated versioning**: Semantic versioning from Conventional Commits
- **Container-first**: Multi-platform Docker builds with layer caching
- **Deployment automation**: Staging + Production with health checks & rollback
- **Monitoring**: Periodic image scanning + continuous health monitoring

### Pipeline Stages
1. **CI** (Continuous Integration)
   - Language detection
   - Build & test
   - Code coverage
   - SCA (Software Composition Analysis)
   - SBOM generation (CycloneDX)
   - Code quality (CodeQL + SonarQube)

2. **Build** (Docker Packaging)
   - Multi-platform builds (amd64, arm64)
   - Layer caching
   - SBOM attachment
   - Image signing

3. **Deploy** (Staging)
   - Docker Compose deployment
   - Health checks
   - Smoke tests
   - Log aggregation

4. **DAST** (Dynamic Application Security Testing)
   - OWASP ZAP full scan
   - Severity-based gating
   - SARIF conversion
   - Issue auto-creation

5. **Approval** (Manual Gate)
   - Production approval environment
   - Reviewer signoff

6. **Deploy** (Production)
   - Pre-deployment checks
   - Blue-green deployment support
   - Health verification
   - Rollback capability

7. **Monitor** (Continuous Monitoring)
   - Health checks
   - Compliance verification
   - Synthetic tests
   - SBOM traceability

8. **Version** (Release Automation)
   - Conventional Commit analysis
   - Semantic version calculation
   - Version file updates
   - Automated PR creation

9. **Release** (Tag Creation)
   - Git tag creation
   - Release notes generation
   - GitHub Release publishing

10. **Scan** (Periodic Image Scanning)
    - Grype vulnerability scanning
    - Issue auto-triage
    - SARIF upload
    - Non-blocking gate

---

## 🚀 Quick Start

### For Template Repository Maintainers

1. **Clone and configure**:
   ```bash
   git clone https://github.com/DEBARPAN2000/CI-CD.git
   cd CI-CD
   ```

2. **Verify workflows**:
   ```bash
   ls .github/workflows/
   # Should show: ci.yml, docker-build-push.yml, dast-smoke.yml, etc.
   ```

3. **Customize (optional)**:
   - Edit `.github/workflows/main-pipeline.yml` for your defaults
   - Update `docker/Dockerfile.dotnet` and `docker/Dockerfile.python` for your base images

### For Consumer Repositories

#### Step 1: Copy Example Workflow
Choose your stack:

**For .NET projects:**
```bash
# Copy .NET example to your repo
cp examples/dotnet-consumer-workflow.yml .github/workflows/ci-cd-pipeline.yml
```

**For Python projects:**
```bash
# Copy Python example to your repo
cp examples/python-consumer-workflow.yml .github/workflows/ci-cd-pipeline.yml
```

#### Step 2: Update Workflow References
Replace `DEBARPAN2000` with your organization:
```yaml
uses: YOUR-ORG/CI-CD/.github/workflows/ci.yml@main
```

#### Step 3: Configure Secrets
Set these at org or repo level:

**Required for all repos:**
- `GITHUB_TOKEN` (built-in, auto-available)

**Optional for enhanced scanning:**
- `SONAR_HOST_URL`: SonarQube server URL
- `SONAR_TOKEN`: SonarQube project token

**For private registries:**
- `REGISTRY_USERNAME`: Docker registry user
- `REGISTRY_PASSWORD`: Docker registry password

#### Step 4: Create Deployment Configuration
Add to your repo root:

**docker-compose.staging.yml**:
```yaml
version: '3.8'
services:
  app:
    image: ${IMAGE_REF:-ghcr.io/org/app:latest}
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 3
```

**docker-compose.yml** (production):
```yaml
version: '3.8'
services:
  app:
    image: ${IMAGE_REF:-ghcr.io/org/app:latest}
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    environment:
      - ASPNETCORE_URLS=http://+:8080
```

#### Step 5: Add Branch Protection Rules
For `main` branch:
- ✅ Require status checks to pass: `CI (.NET)` or `CI (Python)`
- ✅ Require at least 1 approval review
- ✅ Dismiss stale PR approvals
- ✅ Require branches to be up to date before merging

#### Step 6: Configure GitHub Environments

**Staging environment** (Settings → Environments → New environment):
- Name: `staging`
- Deployment branches: `main`
- No approval required

**Production environment**:
- Name: `production`
- Deployment branches: `main`
- ✅ Require reviewers (2+ recommended)
- Reviewers: Select trusted team members

**Production approval gate**:
- Name: `production-approval`
- Deployment branches: `main`
- ✅ Require reviewers
- Reviewers: Release managers

#### Step 7: Test Workflow
Push to `main` and monitor:
```bash
git push origin main
# Watch Actions tab for workflow execution
```

---

## 📋 Workflow Inputs Reference

### CI Workflow (ci.yml)

```yaml
- language: 'auto' | 'dotnet' | 'python'  # Default: auto
- dotnet-version: '8.0.x'                  # .NET SDK version
- dotnet-project: '.'                      # Project root
- python-version: '3.12'                   # Python version
- python-workdir: '.'                      # Working directory
- python-test-command: ''                  # Override pytest
- lint-command: ''                         # Custom linter
- codeql-languages: 'cpp,csharp,go,java,javascript,python,ruby'  # Narrow to your stack, e.g. 'python'
- run-sonarqube: false                     # Enable SonarQube
- sonar-project-key: ''                    # SQ project key
```

### Docker Build (docker-build-push.yml)

```yaml
- language: 'auto' | 'dotnet' | 'python'
- registry: 'ghcr.io'                      # Container registry
- image-owner: ''                          # Defaults to github.repository_owner for GHCR, omitted otherwise
- image-name: 'my-app'                     # Image name (repo name if empty)
- image-tag: 'latest'                      # Image tag
- tag-latest: true                         # Also move :latest (false for PR builds)
- build-context: '.'                       # Docker build context
- dockerfile-path: ''                      # Custom Dockerfile path
- dotnet-version: '8.0'                    # For template Dockerfile
- python-version: '3.12'                   # For template Dockerfile
```

### Deploy Staging (deploy-staging.yml)

```yaml
- image-ref: ''                            # Optional full image reference override
- registry: 'ghcr.io'                      # Used when image-ref is omitted
- image-owner: ''                          # Defaults to github.repository_owner for GHCR, omitted otherwise
- image-name: ''                           # Defaults to repo name (lowercased for GHCR)
- image-tag: ''                            # Defaults to github.sha
- environment-name: 'staging'
- compose-file: 'docker-compose.staging.yml'
- compose-service: 'app'
- health-check-url: 'http://localhost/health'
- health-check-max-retries: '30'
- health-check-delay: '10'
- tls-cert: false                          # Generate ./certs/{cert,key}.pem for HTTPS apps (compose mounts ./certs)
```

### DAST Scan (dast-smoke.yml)

```yaml
- target-url: (required)                   # URL to scan
- dast-threshold: 'medium' | 'high' | 'critical'
- smoke-endpoints: '/health,/api/status'   # Comma-separated
- image-ref: ''                            # If set, the app is started from this image via compose inside the DAST job
- compose-file: 'docker-compose.staging.yml'
- compose-service: 'app'
- tls-cert: false                          # Generate ./certs for HTTPS apps (self-signed; smoke/health checks use curl -k)
```

### Deploy Production (deploy-production.yml)

```yaml
- image-ref: ''                            # Optional full image reference override
- registry: 'ghcr.io'                      # Used when image-ref is omitted
- image-owner: ''                          # Defaults to github.repository_owner for GHCR, omitted otherwise
- image-name: ''                           # Defaults to repo name (lowercased for GHCR)
- image-tag: ''                            # Defaults to github.sha
- environment-name: 'production'
- compose-file: 'docker-compose.yml'
- compose-service: 'app'
- health-check-url: 'http://localhost/health'
- health-check-max-retries: '30'
- health-check-delay: '10'
- tls-cert: false                          # Generate ./certs/{cert,key}.pem for HTTPS apps
```

For non-GHCR registries, set `image-owner` when the repository path includes a namespace or owner segment; leave it empty only for top-level image paths.

### Version Bump (version-bump.yml)

```yaml
- language: 'auto' | 'dotnet' | 'python'
- version-file-dotnet: 'Directory.Build.props'
- version-file-python: 'pyproject.toml'
- base-branch: 'main'
```

### Release Tag (release-tag.yml)

```yaml
- language: 'auto'
- version-file-dotnet: 'Directory.Build.props'
- version-file-python: 'pyproject.toml'
- release-notes-file: 'CHANGELOG.md'
```

### Periodic Scan (image-periodic-scan.yml)

```yaml
- registry: 'ghcr.io'
- image-name: (required)
- tags-to-scan: 'latest,v1.0.0'            # Comma-separated
- fail-on-critical: false                  # Don't block release
```

### Continuous Monitoring (continuous-monitoring.yml)

```yaml
- image-ref: ''                            # Optional full image reference override
- registry: 'ghcr.io'                      # Used when image-ref is omitted
- image-owner: ''                          # Defaults to github.repository_owner for GHCR, omitted otherwise
- image-name: ''                           # Defaults to repo name (lowercased for GHCR)
- image-tag: ''                            # Defaults to github.sha
- monitoring-url: 'http://localhost/health'
- check-interval: '60'                     # seconds
- max-checks: '3'
- sbom-file: ''                            # Optional
```

---

## 🔐 Security Considerations

### Secrets Management
- Store secrets in GitHub org/repo settings
- Use environment-specific secrets for production
- Rotate credentials regularly
- Never commit `.env` or credential files

### DAST Configuration
- Adjust `dast-threshold` based on risk profile
- Periodic scans don't block releases (info-only)
- Critical findings auto-create GitHub issues
- Review findings in Security tab

### Image Scanning
- Grype scans run on schedule (weekly recommended)
- Non-blocking to allow patch cycles
- Vulnerability trends tracked over time

### Branch Protection
- Require at least 1 approval before merge
- Status checks: All CI jobs must pass
- Enforce latest main before merge

---

## 📊 Pipeline Flow

```
PR/Push to main
    ↓
[1] CI (build, test, SBOM, CodeQL)
    ↓
[2] Docker Build (multi-platform, cache)
    ↓
[3] Deploy Staging (health checks)
    ↓
[4] DAST Scan (OWASP ZAP)
    ↓
[5] ⏳ Approval Gate (manual)
    ↓
[6] Deploy Production (blue-green, rollback)
    ↓
[7] Continuous Monitoring (health, compliance)
    ↓
[8] Version Bump (semver from commits, auto-PR)
    ↓
[9] Release Tag (git tag, release notes)
    ↓
[10] Periodic Scan (scheduled, non-blocking)
```

---

## 🛠️ Troubleshooting

### Workflow Not Triggering
- ✅ Ensure branch is `main`
- ✅ Check `.github/workflows/` exists
- ✅ Verify workflow YAML syntax
- ✅ Check branch protection rules

### DAST Scan Failures
- ✅ Ensure staging deployment is healthy
- ✅ Verify health endpoint is responding
- ✅ Check ZAP timeout settings (10-15 min typical)
- ✅ Lower `dast-threshold` to `low` for debugging

### Docker Build Failures
- ✅ Check Dockerfile exists or use templates
- ✅ Verify build arguments match Dockerfile
- ✅ Ensure registry credentials are set
- ✅ Check image naming conventions (lowercase)

### Version Bump Issues
- ✅ Ensure main branch has version file (Directory.Build.props or pyproject.toml)
- ✅ Verify Conventional Commit format: `feat:`, `fix:`, `BREAKING CHANGE:`
- ✅ Check git token has permissions to create PRs

### Health Check Timeouts
- ✅ Increase `health-check-max-retries`
- ✅ Check container logs: `docker-compose logs app`
- ✅ Verify health endpoint is responding within 60s
- ✅ Check port mappings in docker-compose

---

## 📚 Advanced Usage

### Custom SonarQube Integration
1. Set org secrets: `SONAR_HOST_URL`, `SONAR_TOKEN`
2. Enable in workflow:
   ```yaml
   run-sonarqube: true
   sonar-project-key: 'my-org/my-project'
   ```
3. SonarQube will scan and report code quality

### Custom Linting
Override with `lint-command`:
```yaml
lint-command: 'pylint src/ && black --check src/'
```

### Custom Test Commands
Override with `python-test-command` or `dotnet-test-command`:
```yaml
python-test-command: 'pytest tests/ --cov=src --cov-report=xml'
```

### Private Registry
Use custom registry URL and credentials:
```yaml
registry: 'docker.io'  # or private registry
REGISTRY_USERNAME: ${{ secrets.DOCKER_USERNAME }}
REGISTRY_PASSWORD: ${{ secrets.DOCKER_PASSWORD }}
```

### Scheduled Periodic Scans
Create a `.github/workflows/scheduled-scan.yml`:
```yaml
on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly Sunday 2 AM

jobs:
  scan:
    uses: YOUR-ORG/CI-CD/.github/workflows/image-periodic-scan.yml@main
    with:
      image-name: ghcr.io/your-org/your-app:latest
```

---

## 📖 Template Maintenance

### Updating the Template
Push changes to `main` branch. Consumer repos will automatically use latest via `@main` ref.

To use a specific version:
```yaml
uses: DEBARPAN2000/CI-CD/.github/workflows/ci.yml@v1.0.0
```

### Contributing Improvements
- Test locally first
- Document breaking changes
- Update examples
- Tag releases with semantic versioning

---

## 📞 Support

- **Documentation**: See `/docs` folder
- **Examples**: See `/examples` folder
- **Issues**: GitHub Issues in this repo
- **Contact**: Reach out to the DevOps team

---

## 📄 License

MIT License - See LICENSE file

---

## ✅ Checklist for Consumer Repos

- [ ] Copy example workflow to `.github/workflows/`
- [ ] Update `uses:` references for your org
- [ ] Create `docker-compose.staging.yml`
- [ ] Create `docker-compose.yml`
- [ ] Set GitHub secrets (SONAR_HOST_URL, SONAR_TOKEN)
- [ ] Configure GitHub environments (staging, production)
- [ ] Set branch protection rules for `main`
- [ ] Add health check endpoint (`GET /health`)
- [ ] Test workflow on feature branch
- [ ] Merge to `main` and verify full pipeline
- [ ] Monitor first few releases
- [ ] Adjust thresholds and timeouts as needed
