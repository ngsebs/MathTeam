#!/bin/bash
# Stop and remove the Docker container

docker stop pent-eam-math-team 2>/dev/null || true
docker rm pent-eam-math-team 2>/dev/null || true
echo "Container removed."