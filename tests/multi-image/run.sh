#!/usr/bin/env bash
# Exercises the multi-image resolve logic embedded in the reusable workflows.
# Run from the repository root: bash tests/multi-image/run.sh
set -euo pipefail

wf=.github/workflows
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0

extract() { # workflow job step-name -> stdout (the step's run script)
  python3 - "$@" <<'PY'
import sys, yaml
wf, job, step = sys.argv[1:4]
for st in yaml.safe_load(open(wf))['jobs'][job]['steps']:
    if st.get('name') == step:
        print(st['run'])
        break
else:
    sys.exit(f'step {step!r} not found in {wf}:{job}')
PY
}

check() { # description, then a command that must succeed
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then echo "  ✓ $desc"; else echo "  ✗ $desc" >&2; fail=1; fi
}
check_fails() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then echo "  ✗ $desc (expected failure)" >&2; fail=1; else echo "  ✓ $desc"; fi
}

echo "Build workflow: image list"
extract $wf/docker-build-push.yml detect "Resolve images" > "$work/detect.sh"
detect() { # env assignments as args
  : > "$work/out"
  (cd "$work" && touch pyproject.toml && env LANGUAGE=auto DOCKERFILE= IMAGE_NAME= BUILD_CONTEXT=. DOTNET_VERSION=8.0 \
    PYTHON_VERSION=3.12 REPO_NAME=Repo IMAGES_INPUT= "$@" GITHUB_OUTPUT="$work/out" bash "$work/detect.sh")
}
out() { grep "^$1=" "$work/out" | cut -d= -f2-; }

detect >/dev/null
check "single-image mode keeps auto-detection" test "$(out language)" = python
check "single-image mode names the image after the repo" test "$(out names)" = '["repo"]'
detect IMAGE_NAME=swing DOCKERFILE=Dockerfile LANGUAGE=python >/dev/null
check "single-image mode honours dockerfile-path" test "$(out images | jq -r '.[0].dockerfile')" = Dockerfile
check "custom dockerfile does not need the template checkout" test "$(out images | jq -r '.[0]["needs-templates"]')" = false

multi='[
 {"name":"Api","language":"dotnet","role":"service","compose-service":"api","health-url":"http://l/h"},
 {"name":"worker","language":"python","smoke-command":"python -m app --check","build-args":{"X":"1"}},
 {"name":"custom","dockerfile":"docker/Custom.Dockerfile","context":"sub"}]'
detect IMAGES_INPUT="$multi" >/dev/null
check "mixed languages resolve" test "$(out language)" = custom,dotnet,python
check "names are lower-cased" test "$(out names)" = '["api","worker","custom"]'
check "only batch images with a smoke-command are smoke-run" test "$(out smoke | jq -r 'map(.name) | join(",")')" = worker
check "templates picked per language" test "$(out images | jq -r '.[0].dockerfile')" = .ci-cd-templates/docker/Dockerfile.dotnet
check "build-args are merged" test "$(out images | jq -r '.[1]["build-args"]')" = $'DOTNET_VERSION=8.0\nPYTHON_VERSION=3.12\nX=1'
check "context override" test "$(out images | jq -r '.[2].context')" = sub
check_fails "rejects duplicate names" detect IMAGES_INPUT='[{"name":"a","language":"python"},{"name":"A","language":"dotnet"}]'
check_fails "rejects missing language and dockerfile" detect IMAGES_INPUT='[{"name":"a"}]'
check_fails "rejects bad role" detect IMAGES_INPUT='[{"name":"a","language":"python","role":"x"}]'
check_fails "rejects smoke-command on a service" detect IMAGES_INPUT='[{"name":"a","language":"python","role":"service","smoke-command":"x"}]'
check_fails "rejects non-array" detect IMAGES_INPUT='{"name":"a"}'

echo "Deploy/monitor/DAST workflows: service list"
while IFS=: read -r file job; do
  extract "$wf/$file" "$job" "Resolve image references" > "$work/${file%.yml}-$job.sh"
done <<'LIST'
deploy-staging.yml:deploy
deploy-production.yml:pre-deploy-check
deploy-production.yml:deploy
dast-smoke.yml:dast
continuous-monitoring.yml:health-monitoring
continuous-monitoring.yml:compliance-check
LIST
reference=$work/deploy-staging-deploy.sh
for f in "$work"/*-*.sh; do
  [ "$f" = "$work/detect.sh" ] && continue
  check "$(basename "$f" .sh) uses the shared resolve script" diff -q "$reference" "$f"
done

svc() {
  : > "$work/out"
  env REGISTRY=ghcr.io IMAGE_OWNER= REPO_OWNER=Me IMAGE_TAG= SHA=abc IMAGES_INPUT= IMAGE_REF= IMAGE_NAME= REPO_NAME=Repo \
    COMPOSE_SERVICE=app HEALTH_URL=http://l/h REQUIRE_HEALTH=true "$@" GITHUB_OUTPUT="$work/out" bash "$reference"
}
svc >/dev/null
check "single image: repo name + sha" test "$(out services | jq -r '.[0].ref')" = ghcr.io/me/repo:abc
svc IMAGE_REF=docker.io/x/y:1 >/dev/null
check "single image: explicit image-ref wins" test "$(out services | jq -r '.[0].ref')" = docker.io/x/y:1
svc IMAGES_INPUT="$multi" >/dev/null
check "multi: batch images are not deployed" test "$(out services | jq -r 'map(.name) | join(",")')" = api
check "multi: compose-service and key" test "$(out services | jq -r '.[0] | .service + "/" + .key')" = api/API
check "multi: ref uses shared tag" test "$(out services | jq -r '.[0].ref')" = ghcr.io/me/api:abc
check_fails "multi: service without health-url is rejected" svc IMAGES_INPUT='[{"name":"a","role":"service"}]'
check "multi: health-url optional when not required" svc REQUIRE_HEALTH=false IMAGES_INPUT='[{"name":"a","role":"service"}]'
check_fails "multi: no service entries is rejected" svc IMAGES_INPUT='[{"name":"a","language":"python"}]'

if [ "$fail" != 0 ]; then echo "✗ multi-image checks failed" >&2; exit 1; fi
echo "✓ multi-image checks passed"
