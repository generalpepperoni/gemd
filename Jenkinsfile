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
    }
    stages {
        stage('Prepare k8s Namespace') {
            steps {
                script {
                    // Create fresh namespace
                    sh "kubectl create namespace ${env.NAMESPACE} || true"

                    // Add any necessary resources (like image pull secrets)
                    // sh "kubectl create secret docker-registry my-registry-key ... -n ${env.NAMESPACE}"
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

                    // get pod name and wait till it ready (in addition to readiness probe)
                    def getPodName = sh(
                        script: "kubectl get pods -n ${env.K8S_NS} -l app=g emd-core -o jsonpath='{.items[0].metadata.name}'",
                        returnStdout: true
                    ).trim()
                    env.POD_NAME = getPodName

                    waitUntil {
                        def status = sh(
                            script: "kubectl get pod ${env.POD_NAME} -n ${env.K8S_NS} -o jsonpath='{.status.phase}'",
                            returnStdout: true
                        ).trim()
                        return status == "Running"
                    }
                }
            }
        }

        stage('Run Simulation Workflow') {
            steps {
                script {
                    // Define pod template for simulation tasks
                    def simulationPod = podTemplate(
                        cloud: 'kubernetes',
                        namespace: env.K8S_NS,
                        containers: [
                            containerTemplate(
                                name: 'pure-pursuit',
                                image: env.SIM_IMG,
                                command: 'cat',  // Keep container running
                                ttyEnabled: true,
                                resourceRequestCpu: '500m',
                                resourceLimitCpu: '1000m',
                                resourceRequestMemory: '512Mi',
                                resourceLimitMemory: '1Gi'
                            ),
                            containerTemplate(
                                name: 'crosstrack-validation',
                                image: env.SIM_IMG,
                                command: 'cat',
                                ttyEnabled: true,
                                resourceRequestCpu: '300m',
                                resourceLimitCpu: '500m',
                                resourceRequestMemory: '256Mi',
                                resourceLimitMemory: '512Mi'
                            ),
                            volumes: [
                                // volumes placeholder
                            ]
                        ]
                    ) {
                        node(POD_LABEL) {
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
            def cteAvg = sh(
                script: """
                    kubectl exec ${env.POD_NAME} -- bash -lc \
                    "rostopic echo -n 1 /gem/metrics/ct_error_avg_last 2>/dev/null | grep '^data:' | awk '{print \$NF}'"
                """,
                returnStdout: true
            ).trim()

            echo "CTE Average: ${cteAvg}"
            cteAvgFloat = cteAvg.toFloat()
            env.CT_ERROR = cteAvgFloat

            if (cteAvgFloat <= -1.0 || cteAvgFloat >= 1.0) {
                error("CTE average ${cteAvgFloat} is outside acceptable range [-1.0, 1.0]")
            }
        }

        stage('Export to ClickHouse') {
            steps {
                script {
                    // Define pod template for data export
                    def exportPod = podTemplate(
                        cloud: 'kubernetes',
                        containers: [
                            containerTemplate(
                                name: 'data-exporter',
                                image: 'clickhouse/clickhouse-client:latest',
                                ttyEnabled: true,
                                command: 'cat'
                            )
                        ],
                        volumes: [
                            hostPathVolume(hostPath: '/tmp', mountPath: '/tmp/ros')
                        ]
                    )

                    exportPod.node {
                        container('data-exporter') {
                            // Copy CSV from simulator pod
                            sh "kubectl cp ${env.POD_NAME}:/tmp/ros_gem_ct_errors.csv /tmp/ros/ct_errors_extracted.csv"

                            sh """
                            clickhouse-client \
                                --host ${env.CLICKHOUSE_HOST} \
                                --user ${env.CLICKHOUSE_USER} \
                                --password ${env.CLICKHOUSE_PASS} \
                                --query "INSERT INTO ${env.CLICKHOUSE_TABLE} FORMAT CSV" < /tmp/ros//ct_errors_extracted.csv
                            """
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            // Cleanup Helm deployment
            sh 'helm -n ${env.K8S_NS} uninstall gemd || true'
        }
        success {
            emailext (
                subject: 'SUCCESS: GEM Simulation Pipeline',
                body: 'All stages completed successfully. Crosstrack Error = ${env.CT_ERROR}',
                to: 'aleksei.kondrashov94@gmail.com'
            )
        }
        failure {
            emailext (
                subject: 'FAILURE: GEM Simulation Pipeline',
                body: 'One or more stages failed. Crosstrack Error = ${env.CT_ERROR}',
                to: 'aleksei.kondrashov94@gmail.com'
            )
        }
    }
}
