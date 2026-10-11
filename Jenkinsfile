// Example Jenkinsfile for GEMd k8s-ready deployment

/* DISCLAIMER
 *
 * This is an example Jenkinsfile pipeline - ONLY FOR REFERENCE
 */

pipeline {
    agent {
        kubernetes {
            label 'gemd-agent-pod'
            yaml '''
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: helm
    image: alpine/helm:3.12.3
    tty: true
    command: ["cat"]
  - name: kubectl
    image: bitnami/kubectl:1.27.4
    tty: true
    command: ["cat"]
'''
        }
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '50', artifactNumToKeepStr: '10'))
        disableConcurrentBuilds()
        timeout(time: 1, unit: 'HOURS')
    }

    environment {
        SIM_IMG = 'ghcr.io/generalpepperoni/gemd-core'
        SIM_TAG = 'latest'
        K8S_NS = "gemd-dev-${env.BUILD_NUMBER}"

        // Better to create multiple NS with unique names
        // K8S_NS = "gemd-dev-${env.BUILD_NUMBER}"
        // CLICKHOUSE_TABLE = 'gem_cte_metrics'
        // CLICKHOUSE_HOST = 'clickhouse-host'
        // CLICKHOUSE_USER = credentials('clickhouse-user')
        // CLICKHOUSE_PASS = credentials('clickhouse-pass')
    }

    // Pipeline starts here
    stages {

        stage('Checkout SCM') {
            steps {
                checkout scm
            }
        }

        stage('Prepare k8s Namespace') {
            steps {
                container('kubectl') {
                    withCredentials([file(credentialsId: 'kubecfg-gemd', variable: 'KUBECONFIG')]) {
                        sh label: 'Create k8s ns', script: "kubectl create namespace ${K8S_NS} || true"
                    }
                }
            }
        }

        stage('Deploy Gazebo Simulator') {
            steps {
                container('helm') {
                    withCredentials([file(credentialsId: 'kubecfg-gemd', variable: 'KUBECONFIG')]) {
                        script {
                            // Atomic deploy of GEMd Helm chart
                            sh label: 'GEMd Helm chart atomic deploy', script: """
                                helm upgrade --install gemd ./helm \
                                    --namespace ${env.K8S_NS} \
                                    --set image.repository=${env.SIM_IMG} \
                                    --set image.tag=${env.SIM_TAG} \
                                    --atomic \
                                    --wait \
                                    --timeout 10m \
                                    --cleanup-on-fail
                            """
                        }
                    }
                }

                container('kubectl') {
                    withCredentials([file(credentialsId: 'kubecfg-gemd', variable: 'KUBECONFIG')]) {
                        script {
                            // Get pod name
                            waitUntil {
                                def podName = sh(
                                    script: "kubectl get pods -n ${K8S_NS} -l app=gemd-core -o jsonpath='{.items[0].metadata.name}' --field-selector=status.phase=Running 2>/dev/null || true",
                                    returnStdout: true
                                ).trim()
                                return env.POD_NAME != null && !env.POD_NAME.isEmpty()
                            }
                        }
                    }
                }
            }
        }

        // Use different approach with podTemplate in this stage
        stage('Run GEMd simulation') {
            steps {
                script {
                    podTemplate(
                        cloud: 'kubernetes',
                        namespace: K8S_NS,
                        containers: [
                            containerTemplate(
                                name: 'pure-pursuit',
                                image: "${SIM_IMG}:${SIM_TAG}",
                                command: 'cat',
                                ttyEnabled: true,
                                resourceRequestCpu: '500m',
                                resourceLimitCpu: '1000m',
                                resourceRequestMemory: '512Mi',
                                resourceLimitMemory: '1Gi'
                            ),
                            containerTemplate(
                                name: 'crosstrack-validation',
                                image: "${SIM_IMG}:${SIM_TAG}",
                                command: 'cat',
                                ttyEnabled: true,
                                resourceRequestCpu: '300m',
                                resourceLimitCpu: '500m',
                                resourceRequestMemory: '256Mi',
                                resourceLimitMemory: '512Mi'
                            )
                        ]
                    ) {
                        // Run simulator and validation scripts in parallel
                        node(POD_LABEL) {
                            parallel(
                                'Pure Pursuit Simulation': {
                                    container('pure-pursuit') {
                                        sh 'bash -lc "rosrun gem_pure_pursuit_sim pure_pursuit_sim.py"'
                                    }
                                },
                                'Crosstrack Validation': {
                                    container('crosstrack-validation') {
                                        sh 'bash -lc "rosrun gem_pure_pursuit_sim crosstrack_error_validation.py --persist --duration=60"'
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }

        stage('Validate CTE Average') {
            steps {
                script {
                    def cteAvg = sh(
                        script: """
                            kubectl exec ${env.POD_NAME} -n ${K8S_NS} -- bash -lc \
                            "rostopic echo -n 1 /gem/metrics/ct_error_avg_last 2>/dev/null | grep '^data:' | awk '{print \$NF}'"
                        """,
                        returnStdout: true
                    ).trim()

                    echo '======================'
                    echo "CTE Average: ${cteAvg}"
                    echo '======================'

                    float cteAvgFloat = cteAvg.toFloat()
                    env.CT_ERROR_AVG = cteAvg

                    if (cteAvgFloat <= -1.0 || cteAvgFloat >= 1.0) {
                        error("CTE average ${cteAvg} is outside acceptable range [-1.0, 1.0]")
                    }
                }
            }
        }

        // Now lets export our collected data to some DB
        stage('Export to ClickHouse') {
            steps {
                script {
                    podTemplate(
                        cloud: 'kubernetes',
                        namespace: K8S_NS,
                        volumes: [
                            emptyDirVolume(mountPath: '/tmp/ros', volumeName: 'shared-data')
                        ],
                        containers: [
                            containerTemplate(
                                name: 'kubectl',
                                image: 'bitnami/kubectl:1.27.4',
                                ttyEnabled: true,
                                command: 'cat'
                            ),
                            containerTemplate(
                                name: 'data-exporter',
                                image: 'clickhouse/clickhouse-client:21.3.20.1',
                                ttyEnabled: true,
                                command: 'cat'
                            )
                        ]
                    ) {
                        node(POD_LABEL) {
                            container('kubectl') {
                                withCredentials([file(credentialsId: 'kubecfg-gemd', variable: 'KUBECONFIG')]) {
                                    sh "kubectl cp ${env.POD_NAME}:/tmp/ros_gem_ct_errors.csv /tmp/ros/ct_errors_extracted.csv -n ${K8S_NS}"
                                }
                            }

                            container('data-exporter') {
                                withCredentials([
                                    string(credentialsId: 'clickhouse-user', variable: 'CLICKHOUSE_USER'),
                                    string(credentialsId: 'clickhouse-pass', variable: 'CLICKHOUSE_PASS')
                                ]) {
                                    // Export CT Error history Clickhouse with high-performance std input
                                    sh """
                                    clickhouse-client \
                                        --host ${CLICKHOUSE_HOST} \
                                        --user ${CLICKHOUSE_USER} \
                                        --password ${CLICKHOUSE_PASS} \
                                        --query "INSERT INTO ${CLICKHOUSE_TABLE} FORMAT CSV" < /tmp/ros/ct_errors_extracted.csv
                                    """
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                container('helm') {
                    withCredentials([file(credentialsId: 'kubecfg-gemd', variable: 'KUBECONFIG')]) {
                        sh "helm uninstall gemd -n ${K8S_NS} || true"
                    }
                }

                container('kubectl') {
                    withCredentials([file(credentialsId: 'kubecfg-gemd', variable: 'KUBECONFIG')]) {
                        // Also ns can be deleted, if kubectl token allows ns delete operation
                        sh "kubectl delete namespace ${K8S_NS} --ignore-not-found=true || true"
                    }
                }
            }
        }
        success {
            emailext (
                subject: "SUCCESS: GEM Simulation Pipeline - Build #${env.BUILD_NUMBER}",
                body: "All stages completed successfully.\nCrosstrack Error = ${env.CT_ERROR_AVG}",
                to: 'aleksei.kondrashov94@gmail.com'
            )
        }
        failure {
            emailext (
                subject: "FAILURE: GEM Simulation Pipeline - Build #${env.BUILD_NUMBER}",
                body: "One or more stages failed.\nLast CT Error = ${env.get('CT_ERROR_AVG', 'N/A')}",
                to: 'aleksei.kondrashov94@gmail.com'
            )
        }
    }
}
