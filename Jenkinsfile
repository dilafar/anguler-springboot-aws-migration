#!/usr/bin/env groovy
import groovy.json.JsonSlurper

pipeline{
    agent any

    tools {
        maven 'maven3'
    }

    environment {
        AWS_S3_BUCKET = 'cicdbeansnew'
        AWS_EB_APP_NAME = 'emp-my-app'
        AWS_EB_ENVIRONMENT = 'Emp-my-app-env'
        AWS_EB_APP_VERSION = "${BUILD_ID}"
        ARTIFACT_NAME = "employeemanager-v${BUILD_ID}.jar"
        COSIGN_PASSWORD = credentials('cosign-password') 
        COSIGN_PRIVATE_KEY = credentials('cosign-private-key') 
        COSIGN_PUBLIC_KEY = credentials('cosign-public-key')
        SEMGREP_APP_TOKEN = credentials('SEMGREP_APP_TOKEN')
        SEMGREP_PR_ID = "${env.CHANGE_ID}" 
        CR_TOKEN = credentials('cr_cred')    
    }

    stages{
        stage("secret scan"){
            steps {
                script {
                   sh '''
                        docker run --rm -v $(pwd):/pwd trufflesecurity/trufflehog:latest github --repo https://github.com/dilafar/anguler-springboot-aws-migration.git

                   '''
                }
            }
        }
        stage("increment version"){
            steps {
                script {
                    parallel(
                        "Maven Increment": {
                            dir('employeemanager') {
                                    echo "incrimenting app version ..."
                                    sh 'mvn build-helper:parse-version versions:set \
                                        -DnewVersion=\\\${parsedVersion.majorVersion}.\\\${parsedVersion.minorVersion}.\\\${parsedVersion.nextIncrementalVersion} \
                                        versions:commit'
                                  //  incrementPatchVersion()
                                    def matcher = readFile('pom.xml') =~ '<version>(.+)</version>'
                                    def version = matcher[1][1]       
                                    env.IMAGE_VERSION = "$version-$BUILD_NUMBER"
                                    
                            }
                        },
                        "NPM Increment": {
                            dir('employeemanagerfrontend') {                          
                                    sh 'npm version patch --no-git-tag-version'
                                    def packageFile = readFile('package.json')
                                    def jsonParser = new JsonSlurper()
                                    def packageJson = jsonParser.parseText(packageFile)
                                    def appVersion = packageJson.version
                                    echo "Application version: ${appVersion}"    
                            }
                        }
                    )
                         
                }
            }
        }
        stage("Build"){
            steps {
                  script {
                    parallel(
                        "MVN Build": {
                            dir('employeemanager') {
                                    sh 'mvn clean package'
                            }
                        },
                        "NPM Build": {
                            dir('employeemanagerfrontend') {
                                
                                        sh "npm install"
                                
                            }
                        }
                    )
                  }
            }
        }

        stage('Unit Tests - JUnit and JaCoCo'){
           steps {
               dir('employeemanager') {
                    sh "mvn test"
                }
            }
        }

        stage("Code Quality Analysis"){
            steps {
                script {
                    parallel(
                        "Checkstyle Analysis": {
                            dir('employeemanager') {
                                sh 'mvn checkstyle:checkstyle'
                            }
                        },
                        "njsscan": {
                            dir('employeemanagerfrontend') {
                                sh '''
                                         pip3 install --upgrade njsscan
                                         export PATH=$PATH:$HOME/.local/bin
                                         njsscan --exit-warning . --sarif -o njsscan.sarif
                                   '''
                            }
                        }
                    )    
                    }
                }
                post {
                    always {
                        archiveArtifacts artifacts: '**/employeemanagerfrontend/njsscan.sarif', allowEmptyArchive: true
                        archiveArtifacts artifacts: '**/target/checkstyle-result.xml', allowEmptyArchive: true
                    }
                }             
            }
        

        stage("SAST - sonar Analysis"){
            environment {
                scannerHome = tool 'sonar6.2'
            }
            steps {
                script {
                    parallel(
                         "sonar Analysis": {
                                    dir('employeemanager') {
                                                withSonarQubeEnv('sonar') {
                                                    sh '''${scannerHome}/bin/sonar-scanner \
                                                                -Dsonar.projectKey=employee \
                                                                -Dsonar.projectName=employee \
                                                                -Dsonar.projectVersion=1.0 \
                                                                -Dsonar.sources=src/ \
                                                                -Dsonar.host.url=http://172.48.16.220/ \
                                                                -Dsonar.java.binaries=target/test-classes/com/employees/employeemanager/ \
                                                                -Dsonar.jacoco.reportsPath=target/jacoco.exec \
                                                                -Dsonar.junit.reportsPath=target/surefire-reports/ \
                                                                -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml \
                                                                -Dsonar.dependencyCheck.jsonReportPath=target/dependency-check-report/dependency-check-report.json \
                                                                -Dsonar.dependencyCheck.htmlReportPath=target/dependency-check-report/dependency-check-report.html \
                                                                -Dsonar.java.checkstyle.reportPaths=target/checkstyle-result.xml

                                                            '''
                                                }   
                                                timeout(time: 1, unit: 'HOURS'){
                                                            waitForQualityGate abortPipeline: true
                                                }         
                                    }
                                },
                                "Semgrep": {                     
                                           sh '''
                                                    docker pull semgrep/semgrep && \
                                                    docker run \
                                                        -e SEMGREP_APP_TOKEN=$SEMGREP_APP_TOKEN \
                                                        -e SEMGREP_PR_ID=$SEMGREP_PR_ID \
                                                        -v "$(pwd):$(pwd)" --workdir $(pwd) \
                                                    semgrep/semgrep semgrep ci --json --output semgrep.json
                                              '''   
                                }

                    )
                }
            }
            post {
                    always {
                        archiveArtifacts artifacts: '**/semgrep.json', allowEmptyArchive: true
                    }
                }   

        }



        stage("Deploy to stage bean"){
           steps {
            script{
                dir('employeemanager') {
                    env.JAR_FILE = sh(script: "ls target/employeemanager-*.jar", returnStdout: true).trim()
                    echo "Found JAR File: ${env.JAR_FILE}"
                    withAWS(credentials: 'awsbean', region: 'us-east-1') {
                     //   sh '''
                    //        pip3 install --user urllib3==1.26.16
                   //         pip3 install --user --upgrade awscli botocore
                   //         export PATH=$HOME/.local/bin:$PATH
                   //     '''
                        sh "aws s3 cp ${env.JAR_FILE} s3://$AWS_S3_BUCKET/$ARTIFACT_NAME"
                        sh 'aws elasticbeanstalk create-application-version --application-name $AWS_EB_APP_NAME --version-label $AWS_EB_APP_VERSION --source-bundle S3Bucket=$AWS_S3_BUCKET,S3Key=$ARTIFACT_NAME'
                        sh 'aws elasticbeanstalk update-environment --application-name $AWS_EB_APP_NAME --environment-name $AWS_EB_ENVIRONMENT --version-label $AWS_EB_APP_VERSION'
                }
            }
            }   
           }
        }

        stage("Vulnerability Scan - Docker") {
            steps {
                script {
                    parallel(
                        "Dependency Scan": {
                            dir('employeemanager') {
                                sh "mvn org.owasp:dependency-check-maven:check"
                            }
                        },
                        "Trivy Scan": {
                            parallel(
                                "Trivy Scan": {
                                    dir('employeemanager') {
                                       sh '''
                                           bash trivy-docker-image-scan.sh
                                       '''
                                    }
                                },
                                "Trivy Scan frontend": {
                                    dir('employeemanagerfrontend') {
                                       sh '''
                                           bash trivy-docker-image-scan.sh
                                       '''
                                    }
                                }
                            )
                        },
                        "OPA Conftest":{
                             parallel(
                                "opa-front": {
                                       dir('employeemanager') {
                                        sh '''
                                            docker run --rm \
                                                -v $(pwd):/project \
                                                openpolicyagent/conftest test --policy dockerfile-security.rego Dockerfile 
                                        '''
                                    }     
                                },
                                "opa-back": {
                                                dir("employeemanagerfrontend") {
                                                sh '''
                                                    docker run --rm \
                                                        -v $(pwd):/project \
                                                        openpolicyagent/conftest test --policy dockerfile-security.rego Dockerfile
                                                '''
                                    }

                                }
                             )
                        },
                        "lint dockerfile":{
                             parallel(
                                "opa-front-lint": {
                                    dir('employeemanager') {
                                        sh '''
                                            docker run --rm -i hadolint/hadolint < Dockerfile | tee hadolint_lint.txt
                                        '''
                                    }
                                },
                                "opa-back-lint": {
                                    dir("employeemanagerfrontend") {
                                    sh '''
                                        docker run --rm -i hadolint/hadolint < Dockerfile | tee hadolint_lint_front.tx
                                    '''
                                }
                            }
                             )     
                        },
                        "RetireJs":{
                                dir('employeemanagerfrontend') {
                                    cache(
                                            maxCacheSize: 250, 
                                            caches: [
                                                arbitraryFileCache(
                                                    path: 'node_modules', 
                                                    cacheValidityDecidingFile: 'package-lock.json' 
                                                )
                                            ]
                                    ) {
                                         sh '''
                                            npm install  retire
                                            npm install
                                            npx retire --path . --outputformat json --outputpath retire.json
                                        '''
                                    }
                                }
                            }
                        )
                    }
            }
            post {
                    always {
                        archiveArtifacts artifacts: '**/employeemanagerfrontend/retire.json', allowEmptyArchive: true
                        archiveArtifacts artifacts: '**/employeemanager/target/dependency-check-report/dependency-check-report.json', allowEmptyArchive: true
                    }
                } 
        }

        stage("Node.js Image Build") {
                steps {
                        script {
                            // Clean up unused Docker resources
                            sh 'docker system prune -a --volumes --force || true'

                            withCredentials([usernamePassword(credentialsId: 'docker', passwordVariable: 'PASS', usernameVariable: 'USER')]) {
                                parallel(
                                    "frontend-image-scan": {
                                        dir('employeemanagerfrontend') {
                                            script {
                                                sh '''
                                                    docker build -t fadhiljr/nginxapp:employee-frontend-v$IMAGE_VERSION .
                                                    echo $PASS | docker login -u $USER --password-stdin
                                                    docker push fadhiljr/nginxapp:employee-frontend-v$IMAGE_VERSION
                                                '''
                                                sh 'cosign version'
                                                sh '''
                                                    IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' fadhiljr/nginxapp:employee-frontend-v$IMAGE_VERSION)
                                                    echo "Image Digest: $IMAGE_DIGEST"
                                                    echo "y" | cosign sign --key $COSIGN_PRIVATE_KEY $IMAGE_DIGEST
                                                    cosign verify --key $COSIGN_PUBLIC_KEY $IMAGE_DIGEST
                                                '''
                                            }
                                        }
                                    },
                                    "backend-image-scan": {
                                        dir('employeemanager') {
                                            script {
                                                sh '''
                                                    docker build -t fadhiljr/nginxapp:employee-backend-v$IMAGE_VERSION .
                                                    echo $PASS | docker login -u $USER --password-stdin
                                                    docker push fadhiljr/nginxapp:employee-backend-v$IMAGE_VERSION
                                                '''
                                                sh 'cosign version'
                                                sh '''
                                                    IMAGE_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' fadhiljr/nginxapp:employee-backend-v$IMAGE_VERSION)
                                                    echo "Image Digest: $IMAGE_DIGEST"
                                                    echo "y" | cosign sign --key $COSIGN_PRIVATE_KEY $IMAGE_DIGEST
                                                    cosign verify --key $COSIGN_PUBLIC_KEY $IMAGE_DIGEST
                                                '''
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    }
                }


         stage("change image in kubeconfig") {
            steps {
                script {
                    parallel(
                        "Change image backend": {           
                            dir('kustomization') {
                                script {
                                    sh '''
                                        sed -i "/containers:/,/^[^ ]/s|image:.*|image: fadhiljr/nginxapp:employee-backend-v$IMAGE_VERSION|g" backend-deployment.yml
                                        sed -i "s|image:.*|image: fadhiljr/nginxapp:employee-frontend-v$IMAGE_VERSION|g" frontend-deployment.yml
                                        cat backend-deployment.yml
                                        cat frontend-deployment.yml
                                    '''
                                }
                            }
                        },
                        "DefectDojo Uploader": {
                            script {
                                sh '''
                                    pip install --upgrade urllib3 chardet requests
                                '''
                            }
                            parallel(
                                "Frontend Reports Upload": {
                                    dir('employeemanagerfrontend') {
                                        script {
                                            // python3 upload-reports.py semgrep.json 
                                            sh '''                                           
                                                python3 upload-reports.py njsscan.sarif
                                                python3 upload-reports.py retire.json
                                            '''
                                        }
                                    }
                                },
                                "Backend Reports Upload": {
                                    dir('employeemanager') {
                                        script {
                                            sh '''
                                               echo "python3 upload-reports.py /target/dependency-check-report/dependency-check-report.json"
                                            '''
                                        }
                                    }
                                }
                            )
                        }
                    )
                }
            }

        }

         stage("Vulnerability Scan - kubernetes") {
            steps {
                script {
                        parallel (
                           // "OPA Scan": {
                          //          sh '''
                         //               docker run --rm \
                         //                   -v $(pwd):/project \
                        //                    openpolicyagent/conftest test --policy opa-k8s-security.rego kustomization/*
                        //            '''
                        //    },
                            "Trivy Scan": {
                                        sh ''' 
                                            bash trivy-k8s-scan.sh fadhiljr/nginxapp:employee-frontend-v$IMAGE_VERSION &
                                            bash trivy-k8s-scan.sh fadhiljr/nginxapp:employee-backend-v$IMAGE_VERSION &

                                            wait
                                       '''                           
                            },
                           "kubescape": {
                                dir('kustomization') {
                                        script {
                                            sh '''
                                                kubescape scan framework nsa .
                                            '''
                                        }
                                }
                            }
                        )
                    }
            }
        }
        stage("Kubernetes Apply") {
            steps {
                script {
                         withKubeConfig([credentialsId: 'kubeconfig']) {
                            sh "kubectl apply -k kustomization/"
                            sh "kubectl apply -f kustomization/ingress.yml"
                        }

                    }
                }
            
        }

        stage ("kubernetes cluster check") {
            steps {
                script {
                        withKubeConfig([credentialsId: 'kubeconfig']) {
                                parallel (
                                        "kubernetes CIS benchmark": {
                                            sh '''
                                                kubescape scan framework all
                                            '''
                                        },
                                        "kubernetes cluster scan": {
                                            sh '''
                                                kubescape scan
                                            '''
                                        },
                                        "kubenetes resource scan": {
                                            sh '''
                                                kubescape scan workload Deployment/employee-frontend 
                                                kubescape scan workload service/employee-frontend-service
                                            '''
                                        }
                                )
                        }
                }
            }
        }

        stage("commit change") {
            steps {
                script {
                    sshagent(['git-ssh-auth']) {
                            sh '''
                                mkdir -p ~/.ssh
                                ssh-keyscan -H github.com >> ~/.ssh/known_hosts
                                git remote set-url origin git@github.com:dilafar/anguler-springboot-aws-migration.git
                                git pull origin master || true
                                git add .
                                git commit -m "change added"
                                git push origin HEAD:master
                            '''
                    }
                }
            }
        }

      

    }

    post {
        always {
            dependencyCheckPublisher pattern: '**/employeemanager/target/dependency-check-report/dependency-check-report.json'
        }
    }
}

