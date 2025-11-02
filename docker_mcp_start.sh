#!/usr/bin/env bash
set -euo pipefail

echo "=== Docker MCP Gateway Launcher ==="
echo

# Check if Docker Desktop is running
if ! docker info >/dev/null 2>&1; then
  echo "Starting Docker Desktop..."
  open -a Docker
  until docker info >/dev/null 2>&1; do 
    echo "Waiting for Docker engine..."
    sleep 3
  done
  echo "✅ Docker Desktop is running"
fi

# Ensure correct context
docker context use desktop-linux 2>/dev/null || true

# Initialize catalog if needed
docker mcp catalog init || true

echo
echo "Launching MCP Gateway..."
echo "Press Ctrl+C to stop"
echo

# Run the gateway
exec docker mcp gateway run --verbose
