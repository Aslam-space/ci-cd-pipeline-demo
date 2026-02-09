pipeline {
    agent any

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                echo "CI pipeline triggered by GitHub push"
            }
        }
    }
}
