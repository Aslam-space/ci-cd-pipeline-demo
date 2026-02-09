pipeline {
    agent any

    environment {
        // GitHub repository
        REPO_URL = 'https://github.com/Aslam-space/ci-cd-pipeline-demo.git'
        BRANCH = 'main'

        // Docker image details
        IMAGE_NAME = 'ci-cd-demo'
        AWS_ACCOUNT_ID = '357225327957'
        AWS_REGION = 'ap-south-1'
        ECR_REPO = 'ci-cd-demo-repo'

        // AWS credentials stored in Jenkins credentials manager
        AWS_CREDENTIALS = 'aws-cred-id'

        // For dynamic HTML integration
        BUILD_NUMBER_FILE = 'build_info.txt'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
    }

    stages {
        stage('Checkout') {
            steps {
                echo "Cloning repo..."
                git branch: "${BRANCH}", url: "${REPO_URL}"
            }
        }

        stage('Build Docker Image') {
            steps {
                echo "Building Docker image..."
                sh '''
                    docker build -t ${IMAGE_NAME}:${BUILD_NUMBER} .
                '''
            }
        }

        stage('Test Image') {
            steps {
                echo "Checking Docker image..."
                sh '''
                    docker images | grep ${IMAGE_NAME}
                '''
            }
        }

        stage('Push to AWS ECR') {
            steps {
                echo "Logging in and pushing to ECR..."
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "${AWS_CREDENTIALS}"]]) {
                    sh '''
                        aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
                        docker tag ${IMAGE_NAME}:${BUILD_NUMBER} ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${BUILD_NUMBER}
                        docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${BUILD_NUMBER}
                    '''
                }
            }
        }

        stage('Generate Dynamic Info for HTML') {
            steps {
                echo "Updating build info for dynamic website..."
                sh '''
                    echo "BUILD_NUMBER=${BUILD_NUMBER}" > ${BUILD_NUMBER_FILE}
                    echo "GIT_COMMIT=$(git rev-parse --short HEAD)" >> ${BUILD_NUMBER_FILE}
                    echo "STATUS=SUCCESS" >> ${BUILD_NUMBER_FILE}
                '''
            }
        }

        stage('Deploy') {
            steps {
                echo "Deploying container (placeholder)..."
                sh '''
                    # Add your deployment commands here, e.g., ECS update-service
                    echo "Deploy step to implement"
                '''
            }
        }
    }

    post {
        success {
            echo "✅ Build #${BUILD_NUMBER} succeeded!"
        }
        failure {
            echo "❌ Build #${BUILD_NUMBER} failed!"
            sh '''
                echo "STATUS=FAILED" >> ${BUILD_NUMBER_FILE}
            '''
        }
        always {
            archiveArtifacts artifacts: '**/target/*.jar', allowEmptyArchive: true
            cleanWs()
        }
    }
}
