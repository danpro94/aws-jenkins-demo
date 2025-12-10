AWS Free Tier 환경에서 **Jenkins(EC2) 1대 + Docker + EC2 2대**를 이용해
간단한 Python(FastAPI) 앱을 **CI → Docker build & push → EC2 두 대에 배포**까지 자동화하는
레거시형 CI/CD 데모 프로젝트입니다.

*본 프로젝트 완료후 AWS EC2, VPC 등 Resource는 모두 Terminated 됨.*

---

## 1. 아키텍처 개요

- **GitHub**: 이 리포 (`aws-jenkins-demo`)
- **Jenkins Server (EC2)**
    - Jenkins + Docker 엔진 설치
    - GitHub Web UI에서 파이프라인 job 생성
    - Pipeline Script from SCM (Jenkinsfile)
- **App Server 1 (EC2: my-inst-app01)**
    - Docker로 FastAPI 컨테이너 실행
    - 예시: `http://43.201.71.39:8080`
- **App Server 2 (EC2: my-inst-app02)**
    - Docker로 FastAPI 컨테이너 실행
    - 예시: `http://43.200.179.18:8080`
- **Docker Hub**
    - 이미지: `danpro94/aws-jenkins-demo:latest`

### 1.1. 논리 구조

```
Developer (Git push)
      │
      ▼
GitHub (aws-jenkins-demo)  ──▶  Jenkins (Pipeline)
      │                             │
      │                             ├─ Docker build
      │                             ├─ Docker push -> Docker Hub
      │                             └─ SSH 배포 (ssh-agent)
      ▼
 Docker Hub  ─────▶  App01 (EC2) ──▶  :8080 서비스
                └─▶  App02 (EC2) ──▶  :8080 서비스
```

> DoD 스크린샷:
- Jenkins 성공 빌드: `docs/dod-jenkins-green-build01.png`, `docs/dod-jenkins-green-build02.png`
- App01/02 인스턴스 화면: `docs/dod-app01-instance.png`, `docs/dod-app02-instance.png`
- App01/02 응답 화면: `docs/dod-app01-hello.png`, `docs/dod-app02-hello.png`
- Docker Hub 이미지 화면: `docs/dod-dockerhub-image.png`
> 

---

## 2. 사용 스택 및 버전

- AWS EC2: t3.small & micro (Free Tier), Seoul Region - ap-northeast-2
- Jenkins: 2.528.2
- Docker: 최신 CE 패키지
- Python: 3.12 (컨테이너 내부)
- App Framework: FastAPI + Uvicorn
- Jenkins Pipeline: Declarative Pipeline + SSH Agent Plugin

---

## 3. 사전 준비

1. **AWS 계정 (Free Tier)**
2. **GitHub 계정**
3. **Docker Hub 계정**
4. 로컬 PC/git/ssh 사용 가능 (Windows + MobaXterm 또는 WSL)

---

## 4. AWS 인프라 구성

### 4.1 VPC & 네트워크

**1) Main VPC**

- **Name**: `my-vpc`
- **IPv4 CIDR**: `172.31.0.0/16`
- **Region**: `ap-northeast-2` (Seoul)

**2) Subnet 2개**

1. **First Subnet** – Jenkins Server 용
    - Name: `my-subnet-public01`
    - IPv4 CIDR: `172.31.0.0/24`
    - AZ: `ap-northeast-2a`
2. **Second Subnet** – App Server 2대 용
    - Name: `my-subnet-public02`
    - IPv4 CIDR: `172.31.1.0/24`
    - AZ: `ap-northeast-2c`

**3) Internet Gateway**

- **Name**: `my-igw`
- **작업**: `my-vpc` 에 attach

**4) Route Table 2개**

1. **First Routing Table** – Subnet1(public01)에 연결
    - Name: `my-route1-public`
    - Routes:
        - `0.0.0.0/0` → `my-igw`
        - `172.31.0.0/16` → `local`
    - Subnet association: `my-subnet-public01`
2. **Second Routing Table** – Subnet2(public02)에 연결
    - Name: `my-route2-public`
    - Routes:
        - `0.0.0.0/0` → `my-igw`
        - `172.31.0.0/16` → `local`
    - Subnet association: `my-subnet-public02`
    
    ### 4.2 EC2 인스턴스 3대
    
    ### 공통 사항
    
    - OS: Amazon Linux 2023 (또는 호환되는 AMI)
    - VPC: `my-vpc`
    - 퍼블릭 IP 자동 할당: **활성화** (데모용; 실제 운영은 탄력적 IP 권장)
    
    **(1) Jenkins Server 인스턴스**
    
    - **Name**: `my-inst-jenkins`
    - **Instance Type**: `t3.**small`** 또는 `t3.medium` (2 vCPU / 4GB RAM / 8GB EBS 이상 권장)
    - **Subnet**: `my-subnet-public01`
    - **Key Pair**: `my-inst-jenkins` (같은 이름으로 생성)
    - **Security Group**: `my-sg-jenkins`
        - Inbound
            - TCP 22 (SSH): `My IP`
            - TCP 8080 (Jenkins UI): `My IP`
        - Outbound
            - All traffic: 0.0.0.0/0
    
    ---
    
    **(2) App Server 1 인스턴스**
    
    - **Name**: `my-inst-app01`
    - **Instance Type**: `t3.micro` (Free Tier 범위)
    - **Subnet**: `my-subnet-public02`
    - **Key Pair**: (필요시 Jenkins와 동일 키 사용 – 데모용, 운영에선 분리 권장됨)
    - **Security Group**: `my-sg-app01`
        - Inbound
            - TCP 22 (SSH): `My IP`
            - TCP 8080 (App 포트): `0.0.0.0/0` (누구나 접근 – 데모용)
        - Outbound
            - All traffic: 0.0.0.0/0
    
    ---
    
    **(3) App Server 2 인스턴스**
    
    - **Name**: `my-inst-app02`
    - **Instance Type**: `t3.micro`
    - **Subnet**: `my-subnet-public02`
    - **Key Pair**: 위와 동일 키 사용 (데모용)
    - **Security Group**: `my-sg-app02`
        - Inbound
            - TCP 22 (SSH): `My IP`
            - TCP 8080 (App 포트): `0.0.0.0/0`
        - Outbound
            - All traffic: 0.0.0.0/0
    
    ## 5. 애플리케이션 코드 구조
    
    ```
    aws-jenkins-demo/
    ├── app/
    │   ├── main.py
    │   └── requirements.txt
    ├── Dockerfile
    ├── Jenkinsfile
    └── README.md
    ```
    
    ### **5.1 FastAPI 앱**
    
    `app/main.py`
    
    ```python
    from fastapi import FastAPI
    
    app = FastAPI()
    
    @app.get("/")
    def read_root():
        return {"message": "Hello from Jenkins CI/CD demo!"}
    ```
    
    `app/requirements.txt` 
    
    ```
    fastapi
    uvicorn[standard]
    ```
    
    ### 5.2 `Dockerfile`
    
    ```docker
    FROM python:3.12-slim
    
    WORKDIR /app
    
    COPY app/requirements.txt .
    RUN pip install --no-cache-dir -r requirements.txt
    
    COPY app app
    
    CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
    ```
    
    ## 6. Jenkins 서버 세팅 요약
    
    ### 6.1 기본 설치
    
    Jenkins EC2에서:
    
    ```bash
    ssh -i <your-aws-key>.pem ec2-user@<jenkins-ip>
    sudo su -
    
    yum update -y
    yum install -y java-17-amazon-corretto docker git
    systemctl enable --now docker
    
    ```
    
    Jenkins 설치:
    
    ```bash
    wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    yum install -y jenkins
    systemctl enable --now jenkins
    
    usermod -aG docker jenkins
    
    ```
    
    브라우저에서 `http://<jenkins-ip>:8080` 접속 후 초기 세팅.
    
    필수 플러그인:
    
    - Git, Pipeline, Credentials
    - **SSH Agent Plugin**
    
    ### 6.2 Docker Hub / SSH Credentials
    
    1. **Docker Hub Credentials** (`docker-hub-creds`)
        - Kind: Username with password
        - Username: `danpro94` (예시)
        - Password: Docker Hub Access Token
    2. **SSH Credentials** (`app-ssh-key`)
        1. Jenkins 서버에서 `jenkins` 유저로 로그인 후 키 생성:
            
            ```bash
            sudo su - jenkins
            mkdir -m 700 ~/.ssh
            ssh-keygen -t rsa -b 4096 -m pem -C "jenkins-deploy-key"
            cat ~/.ssh/id_rsa.pub
            ```
            
        2. 출력된 **public key** 를 app01/app02 의 `~/.ssh/authorized_keys` 에 추가:
            
            ```bash
            # 각 app 서버에서
            mkdir -p ~/.ssh
            chmod 700 ~/.ssh
            echo "<복사한 공개키>" >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
            ```
            
        3. Jenkins UI → **Manage Jenkins → Credentials → (global) → Add Credentials**
            - Kind: `SSH Username with private key`
            - ID: `app-ssh-key`
            - Username: `ec2-user`
            - Private key: `Enter directly` 선택 후 `~jenkins/.ssh/id_rsa` 전체 내용 붙여넣기
        
        ## 7. **Jenkinsfile (파이프라인)**
        
        ```groovy
        pipeline {
            agent any
        
            environment {
                DOCKER_IMAGE = "danpro94/aws-jenkins-demo" // Docker Hub ID 수정
                DOCKER_TAG   = "latest"
                DOCKER_CREDS = "docker-hub-creds"
                SSH_CREDS    = "app-ssh-key"
        
                // 실제 퍼블릭 IP로 교체
                APP1_HOST = "ec2-user@43.201.71.39"
                APP2_HOST = "ec2-user@43.200.179.18"
            }
        
            stages {
                stage('Checkout') {
                    steps {
                        checkout scm
                    }
                }
        
                stage('Unit tests (optional)') {
                    steps {
                        sh '''
                          if [ -f app/tests ]; then
                            echo "Run tests here"
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
                                                              usernameVariable: 'DOCKER_USER',
                                                              passwordVariable: 'DOCKER_PASSWORD')]) {
                                sh '''
                                  echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USER" --password-stdin
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
        
        ```
        
    
    ## 8. Jenkins Job 생성
    
    1. Jenkins UI → **New Item**
    2. 이름: `demojob01`
    3. 타입: **Pipeline**
    4. Pipeline 설정:
        - Definition: **Pipeline script from SCM**
        - SCM: Git
        - Repository URL: `https://github.com/<your-id>/aws-jenkins-demo.git`
        - Branch: `/main`
        - Script Path: `Jenkinsfile`
    5. 저장 후 **Build Now**
    
    ## 9. Definition of Done (DoD)
    
    - [ ]  Jenkins Job 빌드 성공
    - [ ]  Docker Hub에 이미지 존재
    - [ ]  브라우저에서:
        - [ ]  `http://<app01 IP>:8080`
        - [ ]  `http://<app02 IP>:8080`
        
        ⇒ 접속 및 `{"message":"Hello from Jenkins CI/CD demo!"}` 표시
        
    
    ## 10. Debugging 히스토리 (Error 01~04)
    
    > 실습 중 겪은 장애와 해결 과정 정리.
    > 
    
    ### Error 01 – Git main 브랜치 없음
    
    - **콘솔 핵심**
        
        ```
        fatal: couldn't find remote ref refs/heads/main
        
        ```
        
    - **원인**: GitHub 리포가 빈 상태라 `main` 브랜치 자체가 존재하지 않는데 Jenkins가 `main` 을 checkout 하려고 함.
    - **해결**: 최소 1번 커밋 후 `git push origin main` 실행.
    
    ---
    
    ### Error 02 – Waiting for next available executor (무한 대기)
    
    - **콘솔**
        
        ```
        [Pipeline] node
        Still waiting to schedule task
        Waiting for next available executor
        
        ```
        
    - **추가 정보**: Built-In Node 경고
        
        > Disk space is below threshold of 1.00 GiB. Only 946 MiB left on /tmp.
        > 
    - **원인**:
        - EC2 `/tmp` 전체 크기: 951MiB
        - Jenkins `Free Temp Space Threshold`: 1GiB
            
            → 항상 “임계값보다 작음” → Jenkins가 노드를 offline 처리 → Executor 0개.
            
    - **해결**:
        - Built-In Node → Configure → **Disk Space Monitoring Thresholds**
            - `Free Temp Space Threshold` = `100MiB`
            - `Free Temp Space Warning Threshold` = `200MiB`
        - 노드를 **Bring this node back online** 후 빌드 재실행.
    
    ---
    
    ### Error 03 – Docker Hub push 권한 거부
    
    - **콘솔**
        
        ```
        docker build -t your-dockerhub-id/aws-jenkins-demo:latest .
        docker push your-dockerhub-id/aws-jenkins-demo:latest
        denied: requested access to the resource is denied
        
        ```
        
    - **원인**:
        - Docker Hub 로그인 계정: `danpro94`
        - 푸시 대상 이미지: `your-dockerhub-id/aws-jenkins-demo`
        - 로그인 계정과 repo namespace 불일치.
    - **해결**:
        - `Jenkinsfile` 의 `DOCKER_IMAGE` 값을 실제 계정으로 수정:
            
            ```groovy
            DOCKER_IMAGE = "danpro94/aws-jenkins-demo"
            
            ```
            
    
    ---
    
    ### Error 04 – sshagent: error in libcrypto (ssh-add 실패)
    
    - **콘솔**
        
        ```
        Error loading key "...private_key_...key": error in libcrypto
        ERROR: Failed to run ssh-add
        
        ```
        
    - **원인**: Jenkins SSH Credential 에 저장된 private key 가 깨진 포맷 / 잘못된 키 (pub 키나 암호화된 키 등).
    - **해결**:
        1. `jenkins` 유저로 새 RSA 키 생성 (`ssh-keygen -t rsa -b 4096 -m pem`).
        2. `id_rsa.pub` 를 app01/app02 `authorized_keys` 에 추가.
        3. Jenkins에서 SSH Credentials 를 새 키로 재등록 (`app-ssh-key`).
    
    ## 마무리
    
    이 프로젝트는 **AWS VPC + Jenkins + EC2 배포 패턴**을 하나의 작은 데모로 구현하고,
    
    그 과정에서 발생한 문제와 해결을 모두 남긴 레거시 레퍼런스 입니다.
    
    - 현대 Devops/Cloud Native 환경에서는 EKS, Github Actions, ArgoCD를 사용하는 경우가 많으나, 실제 기업 환경은 여전히 이 구조를 사용할 수 있는 점에 착안하여 진행했습니다.
