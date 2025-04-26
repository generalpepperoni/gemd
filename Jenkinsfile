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
    command: ["/bin/sh", "-c", "--"]
    args: ["while true; do sleep 30; done;"]
    tty: true
  - name: kubectl
    image: bitnami/kubectl:1.27.4
    command: ["/bin/sh", "-c", "--"]
    args: ["while true; do sleep 30; done;"]
    tty: true
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
                        sh script: "kubectl cluster-info", label: "Verify cluster access"
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
    }

    post {
        always {
            container('kubectl') {
                withCredentials([file(credentialsId: 'kubecfg-gemd', variable: 'KUBECONFIG')]) {
                    sh script: "helm uninstall gemd -n ${K8S_NS} || true", label: "Cleanup release"
                    sh script: "kubectl delete namespace ${K8S_NS} || true", label: "Delete namespace"
                }
            }
        }
        success {
            emailext(
                subject: "SUCCESS: GEM Simulation Pipeline",
                body: "All stages completed successfully.\nCrosstrack Error = ${env.CT_ERROR}",
                to: 'aleksei.kondrashov94@gmail.com'
            )
        }
        failure {
            script {
                def ctError = env.CT_ERROR ?: 'N/A'
                emailext(
                    subject: "FAILURE: GEM Simulation Pipeline",
                    body: "One or more stages failed.\nLast CT Error = ${ctError}",
                    to: 'aleksei.kondrashov94@gmail.com'
                )
            }
        }
    }
}