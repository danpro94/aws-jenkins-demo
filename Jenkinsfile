pipeline {
    agent any

    environment {
        DOCKER_IMAGE = "danpro94/aws-jenkins-demo"
        DOCKER_TAG   = "latest"
        DOCKER_CREDS = "docker-hub-creds"      // Docker Hub 자격증명 ID
        SSH_CREDS    = "app-ssh-key"           // app1/app2 SSH 키 ID

        APP1_HOST    = "ec2-user@<app1-ip>"    // 나중에 실제 IP로 교체
        APP2_HOST    = "ec2-user@<app2-ip>"
    }

    stages {

        stage('Checkout') {
            steps {
                // Pipeline from SCM일 경우 checkout scm 으로 충분
                checkout scm
            }
        }

        stage('Unit tests (optional)') {
            steps {
                sh '''
                    if [ -f "app/tests" ]; then
                        echo "Run tests here (pytest 등)"
                    else
                        echo "No tests yet. Skipping."
                    fi
                '''
            }
        }

        stage('Docker build & push') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: env.DOCKER_CREDS,
                                                      usernameVariable: 'DOCKER_USERNAME',
                                                      passwordVariable: 'DOCKER_PASSWORD')]) {
                        sh '''
                            echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
                            docker build -t $DOCKER_IMAGE:$DOCKER_TAG .
                            docker push $DOCKER_IMAGE:$DOCKER_TAG
                        '''
                    }
                }
            }
        }

        stage('Deploy to app1') {
            steps {
                sshagent (credentials: [env.SSH_CREDS]) {
                    sh """
                        ssh -o StrictHostKeyChecking=no $APP1_HOST '
                          docker pull $DOCKER_IMAGE:$DOCKER_TAG &&
                          docker rm -f app || true &&
                          docker run -d --name app -p 8080:8080 $DOCKER_IMAGE:$DOCKER_TAG
                        '
                    """
                }
            }
        }

        stage('Deploy to app2') {
            steps {
                sshagent (credentials: [env.SSH_CREDS]) {
                    sh """
                        ssh -o StrictHostKeyChecking=no $APP2_HOST '
                          docker pull $DOCKER_IMAGE:$DOCKER_TAG &&
                          docker rm -f app || true &&
                          docker run -d --name app -p 8080:8080 $DOCKER_IMAGE:$DOCKER_TAG
                        '
                    """
                }
            }
        }
    }
}

