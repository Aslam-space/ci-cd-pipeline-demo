#!/bin/bash
# redeploy.sh - 9k Professional CI/CD redeploy

# --------------------------
# Detect current public IP
# --------------------------
NEW_IP=$(curl -s http://checkip.amazonaws.com)
echo "Detected new public IP: $NEW_IP"

# --------------------------
# Stop & remove old container
# --------------------------
echo "Stopping and removing old Docker containers..."
docker ps -aq --filter "name=ci-cd-container" | xargs -r docker stop
docker ps -aq --filter "name=ci-cd-container" | xargs -r docker rm

# --------------------------
# Optional: Sync from GitHub
# --------------------------
echo "Syncing latest site from GitHub..."
cd ~/Aslam-space.github.io || exit
git pull origin main

# --------------------------
# Update dynamic metadata
# --------------------------
cd ~/ci-cd-jenkins-docker-aws/app || exit
BUILD_NUMBER=123
GIT_COMMIT=$(git rev-parse --short HEAD)
TIMESTAMP=$(date +%s)

sed -i "s/{{BUILD_NUMBER}}/$BUILD_NUMBER/g" index.html
sed -i "s/{{GIT_COMMIT}}/$GIT_COMMIT/g" index.html
sed -i "s/{{CACHE_BUST}}/$TIMESTAMP/g" index.html

# --------------------------
# Build Docker image
# --------------------------
docker build -t ci-cd-static:latest .

# --------------------------
# Run Docker container
# --------------------------
docker run -d --name ci-cd-container -p 8090:80 ci-cd-static:latest

# --------------------------
# Finished
# --------------------------
echo "Deployment complete!"
echo "Access your site at: http://$NEW_IP:8090"
