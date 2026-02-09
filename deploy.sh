#!/bin/bash
# ==============================
# DevOps CI/CD Full Deploy Script
# ==============================

# VARIABLES
IMAGE_NAME="ci-cd-demo"
CONTAINER_NAME="ci-cd-container"
HOST_PORT=80
CONTAINER_PORT=80
AWS_ACCOUNT_ID="357225327957"
AWS_REGION="ap-south-1"
ECR_REPO="ci-cd-demo"

# STEP 1: Stop and Remove Old Container
echo "🛑 Stopping old container if exists..."
if [ $(docker ps -aq -f name=${CONTAINER_NAME}) ]; then
    docker stop ${CONTAINER_NAME} || true
    docker rm ${CONTAINER_NAME} || true
fi

# STEP 2: Remove Dangling Images
echo "🧹 Cleaning dangling Docker images..."
if [ $(docker images -f "dangling=true" -q) ]; then
    docker rmi $(docker images -f "dangling=true" -q) || true
fi

# STEP 3: Build Docker Image
echo "🐳 Building Docker image..."
docker build -t ${IMAGE_NAME}:latest .

# STEP 4: Run Container Locally
echo "🚀 Running container locally..."
docker run -d --name ${CONTAINER_NAME} -p ${HOST_PORT}:${CONTAINER_PORT} ${IMAGE_NAME}:latest

# STEP 5: Push Image to AWS ECR
echo "☁️ Logging in to AWS ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create ECR repo if not exists
aws ecr describe-repositories --repository-names ${ECR_REPO} --region ${AWS_REGION} >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name ${ECR_REPO} --region ${AWS_REGION}

# Tag and Push
docker tag ${IMAGE_NAME}:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:latest

# STEP 6: Verify Deployment
echo "✅ Deployment Complete. Container Status:"
docker ps -f name=${CONTAINER_NAME}
echo "Website should be live on http://<YOUR_INSTANCE_IP>:${HOST_PORT}"
