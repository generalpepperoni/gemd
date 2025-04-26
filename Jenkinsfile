#!/usr/bin/env groovy

pipeline {
    agent {
        kubernetes {
            label 'gemd-agent-pod'
            yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: helm
    image: alpine/helm:3.12.3
  - name: kubectl
    image: bitnami/kubectl:1.27.4
"""
        }
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '50', artifactNumToKeepStr: '10'))
    }

    environment {
        SIM_IMG = 'ghcr.io/generalpepperoni/gemd-core'
        SIM_TAG = 'latest'
        K8S_NS = "gemd-dev"
        // Better to create multiple NS with unique names
        // K8S_NS = "gemd-dev-${env.BUILD_NUMBER}"
//         CLICKHOUSE_TABLE = 'gem_cte_metrics'
//         CLICKHOUSE_HOST = 'clickhouse-host'
//         CLICKHOUSE_USER = credentials('clickhouse-user')
//         CLICKHOUSE_PASS = credentials('clickhouse-pass')
    }

    stages {
        stage('Configure Kubernetes Access') {
            steps {
                container('kubectl') {
                    withCredentials([file(credentialsId: 'kubecfg-gemd', variable: 'KUBECONFIG')]) {
                        // Verify access
                        sh 'kubectl cluster-info'
                    }
                }
            }
        }

        stage('Prepare k8s Namespace') {
            steps {
                container('kubectl') {
                    withCredentials([file(credentialsId: 'kubecfg-gemd', variable: 'KUBECONFIG')]) {
                        sh "kubectl create namespace ${K8S_NS} || true"
                    }
                }
            }
        }

        stage('Deploy Gazebo Simulator') {
            steps {
                container('helm') {
                    withCredentials([file(credentialsId: 'kubecfg-gemd', variable: 'KUBECONFIG')]) {
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
                    }
                }
            }
        }

//         stage('Run Simulation Workflow') {
//             steps {
//                 script {
//                     podTemplate(
//                         cloud: 'kubernetes',
//                         namespace: K8S_NS,
// //                         label: 'SIMULATION-POD', // Add label for node selection
//                         containers: [
//                             containerTemplate(
//                                 name: 'pure-pursuit',
//                                 image: SIM_IMG,
// //                                 command: 'cat',
//                                 ttyEnabled: true,
//                                 resourceRequestCpu: '500m',
//                                 resourceLimitCpu: '1000m',
//                                 resourceRequestMemory: '512Mi',
//                                 resourceLimitMemory: '1Gi'
//                             ),
//                             containerTemplate(
//                                 name: 'crosstrack-validation',
//                                 image: SIM_IMG,
// //                                 command: 'cat',
//                                 ttyEnabled: true,
//                                 resourceRequestCpu: '300m',
//                                 resourceLimitCpu: '500m',
//                                 resourceRequestMemory: '256Mi',
//                                 resourceLimitMemory: '512Mi'
//                             )
//                         ],
//                         volumes: [
//                             emptyDirVolume(mountPath: '/tmp/ros', memory: false)
//                         ]
//                     ) {
//                         node('SIMULATION-POD') {
//                             parallel(
//                                 "Pure Pursuit Simulation": {
//                                     container('pure-pursuit') {
//                                         sh 'bash -lc "rosrun gem_pure_pursuit_sim pure_pursuit_sim.py"'
//                                     }
//                                 },
//                                 "Crosstrack Validation": {
//                                     container('crosstrack-validation') {
//                                         sh 'bash -lc "rosrun gem_pure_pursuit_sim crosstrack_error_validation.py --persist --duration=60"'
//                                     }
//                                 }
//                             )
//                         }
//                     }
//                 }
//             }
//         }
//
//         stage('Validate CTE Average') {
//             steps {
//                 script {
//                     def cteAvg = sh(
//                         script: """
//                             kubectl exec ${env.POD_NAME} -n ${K8S_NS} -- bash -lc \
//                             "rostopic echo -n 1 /gem/metrics/ct_error_avg_last 2>/dev/null | grep '^data:' | awk '{print \$NF}'"
//                         """,
//                         returnStdout: true
//                     ).trim()
//
//                     echo "======================"
//                     echo "CTE Average: ${cteAvg}"
//                     echo "======================"
//
//                     env.CT_ERROR = cteAvg.toFloat()
//
//                     if (cteAvgFloat <= -1.0 || cteAvgFloat >= 1.0) {
//                         error("CTE average ${cteAvgFloat} is outside acceptable range [-1.0, 1.0]")
//                     }
//                 }
//             }
//         }
    }

    post {
        always {
            container('kubectl') {
                withCredentials([file(credentialsId: 'kubecfg-gemd', variable: 'KUBECONFIG')]) {
                    sh "helm uninstall gemd -n ${K8S_NS} || true"
                    // Also ns can be deleted, if kubectl token allows ns delete operation
                    // sh "kubectl delete namespace ${K8S_NS} || true"
                }
            }
        }
        success {
            emailext (
                subject: "SUCCESS: GEM Simulation Pipeline",
                body: "All stages completed successfully.\nCrosstrack Error = ${env.CT_ERROR}",
                to: 'aleksei.kondrashov94@gmail.com'
            )
        }
        failure {
            emailext (
                subject: "FAILURE: GEM Simulation Pipeline",
                body: "One or more stages failed.\nLast CT Error = ${env.get('CT_ERROR', 'N/A')}",
                to: 'aleksei.kondrashov94@gmail.com'
            )
        }
    }
}