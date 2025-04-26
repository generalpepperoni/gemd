#!/usr/bin/env groovy

pipeline {
    agent any
    environment {
        CLICKHOUSE_TABLE = 'gem_cte_metrics'
        SIM_IMG = 'ghcr.io/generalpepperoni/gemd-core:latest'
        SIM_TAG = 'latest'
        K8S_NS = "gemd-dev"
        // Better to create multiple NS with unique names
        // K8S_NS = "gemd-dev-${env.BUILD_NUMBER}"
//         CLICKHOUSE_HOST = 'clickhouse-host'
//         CLICKHOUSE_USER = credentials('clickhouse-user')
//         CLICKHOUSE_PASS = credentials('clickhouse-pass')
    }
    stages {
        stage('Prepare k8s Namespace') {
            steps {
                script {
                    // Create namespace
                    sh "kubectl create namespace ${K8S_NS} || true"
                }
            }
        }

        stage('Deploy Gazebo Simulator') {
            steps {
                script {
                    // Atomic deploy of GEMd Helm chart
                    sh """
                    helm upgrade --install gemd ./helm \
                        --namespace ${env.K8S_NS} \
                        --set image.repository=${env.SIM_IMG} \
                        --set image.tag=${env.SIM_TAG} \
                        --atomic \
                        --wait \
                        --timeout 10m \
                        --cleanup-on-fail
                    """

                    // Get pod name with retries
                    waitUntil {
                        env.POD_NAME = sh(
                            script: "kubectl get pods -n ${K8S_NS} -l app=gemd-core -o jsonpath='{.items[0].metadata.name}' --field-selector=status.phase=Running",
                            returnStdout: true
                        ).trim()
                        return status == "Running"
                        // return env.POD_NAME != null && !env.POD_NAME.isEmpty()
                    }
                }
            }
        }

        stage('Run Simulation Workflow') {
            steps {
                script {
                    podTemplate(
                        cloud: 'kubernetes',
                        namespace: K8S_NS,
//                         label: 'SIMULATION-POD', // Add label for node selection
                        containers: [
                            containerTemplate(
                                name: 'pure-pursuit',
                                image: SIM_IMG,
                                command: 'cat',
                                ttyEnabled: true,
                                resourceRequestCpu: '500m',
                                resourceLimitCpu: '1000m',
                                resourceRequestMemory: '512Mi',
                                resourceLimitMemory: '1Gi'
                            ),
                            containerTemplate(
                                name: 'crosstrack-validation',
                                image: SIM_IMG,
                                command: 'cat',
                                ttyEnabled: true,
                                resourceRequestCpu: '300m',
                                resourceLimitCpu: '500m',
                                resourceRequestMemory: '256Mi',
                                resourceLimitMemory: '512Mi'
                            )
                        ],
                        volumes: [
                            emptyDirVolume(mountPath: '/tmp/ros', memory: false)
                        ]
                    ) {
                        node('SIMULATION-POD') {
                            parallel(
                                "Pure Pursuit Simulation": {
                                    container('pure-pursuit') {
                                        sh 'bash -lc "rosrun gem_pure_pursuit_sim pure_pursuit_sim.py"'
                                    }
                                },
                                "Crosstrack Validation": {
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

                    echo "======================"
                    echo "CTE Average: ${cteAvg}"
                    echo "======================"

                    env.CT_ERROR = cteAvg.toFloat()

                    if (cteAvgFloat <= -1.0 || cteAvgFloat >= 1.0) {
                        error("CTE average ${cteAvgFloat} is outside acceptable range [-1.0, 1.0]")
                    }
                }
            }
        }

        stage('Export to ClickHouse') {
            steps {
                script {
                    podTemplate(
                        cloud: 'kubernetes',
                        namespace: K8S_NS,
                        containers: [
                            containerTemplate(
                                name: 'data-exporter',
                                image: 'clickhouse/clickhouse-client:latest',
                                ttyEnabled: true,
                                command: 'cat'
                            )
                        ],
                        volumes: [
                            emptyDirVolume(mountPath: '/tmp/ros', memory: false)
                        ]
                    ) {
                        node(POD_LABEL) {
                            container('data-exporter') {
                                sh "kubectl cp ${env.POD_NAME}:/tmp/ros_gem_ct_errors.csv /tmp/ros/ct_errors_extracted.csv -n ${K8S_NS}"

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

    post {
        always {
            script {
                sh "helm uninstall gemd -n ${K8S_NS} || true"

                // Also ns can be deleted, if kubectl token allows ns delete operation
                // sh "kubectl delete namespace ${K8S_NS} || true"
            }
        }
        success {
            emailext (
                subject: "SUCCESS: GEM Simulation Pipeline - Build #${env.BUILD_NUMBER}",
                body: "All stages completed successfully.\nCrosstrack Error = ${env.CT_ERROR}",
                to: 'aleksei.kondrashov94@gmail.com'
            )
        }
        failure {
            emailext (
                subject: "FAILURE: GEM Simulation Pipeline - Build #${env.BUILD_NUMBER}",
                body: "One or more stages failed.\nLast CT Error = ${env.get('CT_ERROR', 'N/A')}",
                to: 'aleksei.kondrashov94@gmail.com'
            )
        }
    }
}