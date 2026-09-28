// CI/CD pipeline: lint → build → smoke test → security scan → push to ECR → health-gated deploy.
//
// Jenkins requirements:
//   - Agent with Docker, the AWS CLI and curl
//   - Plugins: Pipeline, Git, Credentials Binding, CloudBees AWS Credentials, Timestamper
//   - Credential 'aws-cred-id' (AWS access key) allowed to push to ECR
pipeline {
    agent any

    parameters {
        booleanParam(name: 'DEPLOY', defaultValue: true, description: 'Deploy to this host after pushing (main branch only)')
        string(name: 'HOST_PORT', defaultValue: '80', description: 'Host port the live container listens on')
    }

    environment {
        IMAGE_NAME      = 'ci-cd-demo'
        AWS_REGION      = 'ap-south-1'
        ECR_REPO        = 'ci-cd-demo-repo'
        AWS_CREDENTIALS = 'aws-cred-id'
        LOCAL_IMAGE     = "${IMAGE_NAME}:${BUILD_NUMBER}"
        TEST_CONTAINER  = "${IMAGE_NAME}-test-${BUILD_NUMBER}"

        // Pinned tool images: bump deliberately.
        HADOLINT_IMAGE   = 'hadolint/hadolint:v2.12.0-alpine'
        SHELLCHECK_IMAGE = 'koalaman/shellcheck-alpine:v0.10.0'
        TRIVY_IMAGE      = 'aquasec/trivy:0.62.1'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        skipDefaultCheckout()
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    def scmVars = checkout scm
                    env.GIT_SHORT   = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    env.BRANCH      = (env.BRANCH_NAME ?: scmVars.GIT_BRANCH ?: 'unknown').replaceFirst(/^origin\//, '')
                    env.BUILD_DATE  = sh(script: 'date -u +%Y-%m-%dT%H:%M:%SZ', returnStdout: true).trim()
                    currentBuild.description = "${env.BRANCH} @ ${env.GIT_SHORT}"
                }
                echo "Building ${env.BRANCH} @ ${env.GIT_SHORT}"
            }
        }

        stage('Lint') {
            parallel {
                stage('Dockerfile') {
                    steps {
                        sh 'docker run --rm -i "$HADOLINT_IMAGE" hadolint - < Dockerfile'
                    }
                }
                stage('Shell scripts') {
                    steps {
                        sh 'docker run --rm -v "$WORKSPACE:/mnt:ro" -w /mnt "$SHELLCHECK_IMAGE" shellcheck scripts/*.sh'
                    }
                }
            }
        }

        stage('Build') {
            steps {
                sh '''
                    docker build \
                      --pull \
                      --build-arg BUILD_NUMBER="$BUILD_NUMBER" \
                      --build-arg GIT_COMMIT="$GIT_SHORT" \
                      --build-arg GIT_BRANCH="$BRANCH" \
                      --build-arg BUILD_DATE="$BUILD_DATE" \
                      --build-arg BUILD_URL="$BUILD_URL" \
                      -t "$LOCAL_IMAGE" .
                    docker image ls "$LOCAL_IMAGE"
                '''
            }
        }

        stage('Smoke Test') {
            steps {
                sh '''
                    docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
                    docker run -d --name "$TEST_CONTAINER" --read-only --tmpfs /tmp --cap-drop ALL \
                      -p 127.0.0.1::8080 "$LOCAL_IMAGE"
                    PORT="$(docker port "$TEST_CONTAINER" 8080/tcp | head -1 | awk -F: '{print $NF}')"
                    scripts/smoke-test.sh "http://127.0.0.1:${PORT}"
                    docker exec "$TEST_CONTAINER" nginx -t
                '''
            }
            post {
                failure { sh 'docker logs "$TEST_CONTAINER" || true' }
                always  { sh 'docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true' }
            }
        }

        stage('Security Scan') {
            steps {
                sh '''
                    mkdir -p reports
                    # Full report (all severities) for the build record.
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/ \
                      "$TRIVY_IMAGE" image --no-progress --format table "$LOCAL_IMAGE" > reports/trivy.txt
                    # Gate: fail on fixable CRITICAL vulnerabilities.
                    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache/ \
                      "$TRIVY_IMAGE" image --no-progress --exit-code 1 --severity CRITICAL --ignore-unfixed "$LOCAL_IMAGE"
                '''
            }
            post {
                always { archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true }
            }
        }

        stage('Push to ECR') {
            when { expression { env.BRANCH == 'main' } }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS]]) {
                    script {
                        // Look the account up instead of hard-coding it.
                        def account = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
                        env.ECR_REGISTRY = "${account}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                        env.ECR_IMAGE    = "${env.ECR_REGISTRY}/${env.ECR_REPO}"
                    }
                    sh '''
                        aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || \
                          aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION" \
                            --image-scanning-configuration scanOnPush=true >/dev/null

                        aws ecr get-login-password --region "$AWS_REGION" | \
                          docker login --username AWS --password-stdin "$ECR_REGISTRY"

                        for tag in "$BUILD_NUMBER" "$GIT_SHORT" latest; do
                            docker tag "$LOCAL_IMAGE" "$ECR_IMAGE:$tag"
                            docker push "$ECR_IMAGE:$tag"
                        done
                    '''
                }
            }
        }

        stage('Deploy') {
            when {
                allOf {
                    expression { env.BRANCH == 'main' }
                    expression { params.DEPLOY }
                }
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS]]) {
                    sh 'HOST_PORT="$HOST_PORT" AWS_REGION="$AWS_REGION" scripts/deploy.sh "$ECR_IMAGE:$BUILD_NUMBER"'
                }
            }
        }

        stage('Verify') {
            when {
                allOf {
                    expression { env.BRANCH == 'main' }
                    expression { params.DEPLOY }
                }
            }
            steps {
                sh 'scripts/smoke-test.sh "http://127.0.0.1:$HOST_PORT"'
            }
        }
    }

    post {
        success {
            echo "✅ Build #${BUILD_NUMBER} (${env.GIT_SHORT}) succeeded"
        }
        failure {
            echo "❌ Build #${BUILD_NUMBER} (${env.GIT_SHORT}) failed — see the stage logs above"
        }
        always {
            // Local build tags only; the live container keeps its own image reference.
            sh '''
                docker rmi "$LOCAL_IMAGE" >/dev/null 2>&1 || true
                [ -n "$ECR_IMAGE" ] && docker rmi "$ECR_IMAGE:$GIT_SHORT" "$ECR_IMAGE:latest" >/dev/null 2>&1 || true
            '''
            cleanWs()
        }
    }
}
