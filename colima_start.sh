#!/bin/bash

echo "=== Colima/Docker bootstrap (semi-verbose) ==="
echo

echo "=== Step 0: Environment and tool versions ==="
echo "Host: $(uname -srm)"
echo "macOS: $(sw_vers -productVersion)"
echo "Colima: $(colima version)"
echo "Docker: $(docker --version)"
echo "Docker Compose: $(docker compose version)"
echo

echo "=== Step 1: Start Colima (docker runtime) ==="
colima start --runtime docker --arch aarch64 --cpu 4 --memory 4 --disk 60
echo

echo "=== Step 2: Docker contexts (list, select 'colima', show) ==="
docker context ls
docker context use colima
docker context show
echo

echo "=== Step 3: Docker info and basic checks ==="
docker --version
echo
docker system info --format '{{.Name}}  {{.ServerVersion}}  {{.OSType}}/{{.Architecture}}'
echo
docker ps
echo

echo "=== Step 4: Docker Compose version ==="
docker compose version
echo

echo "=== Step 5: Quick test: hello-world ==="
docker run --rm hello-world
echo

echo "=== Step 6: Optional compose sanity test (busybox) ==="
tmpdir=$(mktemp -d) && cd "$tmpdir"
printf "%s\n" "services:" "  hello:" "    image: busybox:1.36" "    command: ['sh','-lc','echo compose-ok && uname -m']" > compose.yaml
docker compose up --quiet-pull --abort-on-container-exit
docker compose down -v --remove-orphans
cd - && rm -rf "$tmpdir"
echo

echo "=== Done ==="
