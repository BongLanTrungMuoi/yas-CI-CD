pipeline {
    agent any

    parameters {
        string(name: 'backoffice_bff', defaultValue: 'main', description: 'Branch for backoffice-bff')
        string(name: 'backoffice_ui', defaultValue: 'main', description: 'Branch for backoffice-ui')
        string(name: 'storefront_bff', defaultValue: 'main', description: 'Branch for storefront-bff')
        string(name: 'storefront_ui', defaultValue: 'main', description: 'Branch for storefront-ui')
        string(name: 'cart', defaultValue: 'main', description: 'Branch for cart')
        string(name: 'customer', defaultValue: 'main', description: 'Branch for customer')
        string(name: 'inventory', defaultValue: 'main', description: 'Branch for inventory')
        string(name: 'location', defaultValue: 'main', description: 'Branch for location')
        string(name: 'media', defaultValue: 'main', description: 'Branch for media')
        string(name: 'order', defaultValue: 'main', description: 'Branch for order')
        string(name: 'payment', defaultValue: 'main', description: 'Branch for payment')
        string(name: 'product', defaultValue: 'main', description: 'Branch for product')
        string(name: 'promotion', defaultValue: 'main', description: 'Branch for promotion')
        string(name: 'rating', defaultValue: 'main', description: 'Branch for rating')
        string(name: 'search', defaultValue: 'main', description: 'Branch for search')
        string(name: 'tax', defaultValue: 'main', description: 'Branch for tax')
        string(name: 'recommendation', defaultValue: 'main', description: 'Branch for recommendation')
        string(name: 'webhook', defaultValue: 'main', description: 'Branch for webhook')
        string(name: 'sampledata', defaultValue: 'main', description: 'Branch for sampledata')
    }

    environment {
        DOCKER_REGISTRY = 'hownamee'
        NS_PREFIX = "dev-${env.BUILD_ID}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scmGit(
                    branches: [[name: 'main']],
                    userRemoteConfigs: [[url: 'https://github.com/Hownameee/yas-CI-CD.git']]
                )
            }
        }

        stage('Initialize') {
            steps {
                script {
                    echo "Adding Helm repositories..."
                    sh """
                        helm repo add stakater https://stakater.github.io/stakater-charts
                        helm repo add postgres-operator-charts https://opensource.zalando.com/postgres-operator/charts/postgres-operator
                        helm repo add strimzi https://strimzi.io/charts/
                        helm repo add akhq https://akhq.io/
                        helm repo add elastic https://helm.elastic.co
                        helm repo add jetstack https://charts.jetstack.io
                        helm repo add grafana https://grafana.github.io/helm-charts
                        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
                        helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
                        helm repo update
                    """

                    def domainOutput = sh(script: "yq -r '.domain' k8s-cd/deploy/cluster-config.yaml", returnStdout: true).trim()
                    if (domainOutput == '__DOMAIN__' || !domainOutput) {
                        domainOutput = 'yas.local.com'
                    }
                    
                    env.DOMAIN = domainOutput
                    
                    def nodeIp = sh(script: "kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}'", returnStdout: true).trim()
                    env.NODE_IP = nodeIp
                }
            }
        }

        stage('Prepare Deployments') {
            steps {
                script {
                    echo "Injecting build prefix ${env.NS_PREFIX} into all configuration files..."
                    sh """
                        find k8s-cd -type f \\( -name "*.yaml" -o -name "*.template.yaml" \\) -exec sed -i "s/__NS_PREFIX__/${env.NS_PREFIX}/g" {} +
                    """
                }
            }
        }

        stage('Deploy Infrastructure') {
            steps {
                script {
                    echo "Deploying Infrastructure with prefix ${env.NS_PREFIX}..."
                    sh """
                        export NS_PREFIX=${env.NS_PREFIX}
                        cd k8s-cd/deploy
                        ./setup-cluster.sh
                        ./setup-redis.sh
                        ./setup-keycloak.sh
                    """
                    
                    echo "Waiting for core infrastructure to be ready..."
                    sleep(time: 30, unit: 'SECONDS')
                }
            }
        }

        stage('Deploy Configuration') {
            steps {
                script {
                    echo "Deploying yas-configuration with prefix ${env.NS_PREFIX}..."
                    sh """
                        export NS_PREFIX=${env.NS_PREFIX}
                        cd k8s-cd/deploy
                        ./deploy-yas-configuration.sh
                    """
                }
            }
        }

        stage('Deploy Applications') {
            steps {
                script {
                    def deployService = { serviceName, isUi, customArgs ->
                        def paramName = serviceName.replace('-', '_')
                        def branchName = params."${paramName}" ?: 'main'
                        
                        def tag = 'latest'

                        if (branchName != 'main' && serviceName != 'swagger-ui') {
                            echo "Fetching latest commit ID for branch ${branchName} of service ${serviceName}"
                            tag = sh(script: "git ls-remote origin ${branchName} | cut -f1", returnStdout: true).trim()
                            if (!tag) {
                                error "Could not find branch ${branchName} on origin"
                            }
                        }

                        def chartPath = "k8s-cd/charts/${serviceName}"
                        def imageTagKey = isUi ? 'ui.image.tag' : 'backend.image.tag'
                        def tagArg = (serviceName == 'swagger-ui') ? "" : "--set ${imageTagKey}=${tag}"

                        echo "Deploying ${serviceName} (Branch: ${branchName} -> Tag: ${tag})..."
                        sh """
                            cd ${chartPath}
                            helm dependency build .
                            helm upgrade --install ${env.NS_PREFIX}-${serviceName} . \
                                --namespace ${env.NS_PREFIX}-yas --create-namespace \
                                ${tagArg} \
                                ${customArgs}
                        """
                    }

                    deployService('backoffice-bff', false, "--set backend.ingress.host=\"backoffice.${env.DOMAIN}\"")
                    deployService('backoffice-ui', true, "")
                    sleep(time: 20, unit: 'SECONDS')

                    deployService('storefront-bff', false, "--set backend.ingress.host=\"storefront.${env.DOMAIN}\"")
                    deployService('storefront-ui', true, "")
                    sleep(time: 20, unit: 'SECONDS')

                    deployService('swagger-ui', false, "--set ingress.host=\"api.${env.DOMAIN}\"")
                    sleep(time: 20, unit: 'SECONDS')

                    def backendCharts = [
                        "cart", "customer", "inventory", "location", "media", "order",
                        "payment", "product", "promotion", "rating", "search", "tax",
                        "recommendation", "webhook", "sampledata"
                    ]

                    for (chart in backendCharts) {
                        deployService(chart, false, "--set backend.ingress.host=\"api.${env.DOMAIN}\"")
                        sleep(time: 20, unit: 'SECONDS')
                    }
                }
            }
        }

        stage('Access Information') {
            steps {
                script {
                    echo "=========================================================="
                    echo "DEPLOYMENT COMPLETE - BUILD #${env.BUILD_ID}"
                    echo "=========================================================="
                    echo "Worker Node IP: ${env.NODE_IP}"
                    echo "Base Domain for this build: ${env.DOMAIN}"
                    echo "----------------------------------------------------------"
                    echo "Please copy and paste the following entries to your /etc/hosts file:"
                    echo "----------------------------------------------------------"
                    
                    echo """${env.NODE_IP} pgadmin.${env.DOMAIN}
${env.NODE_IP} akhq.${env.DOMAIN}
${env.NODE_IP} kibana.${env.DOMAIN}
${env.NODE_IP} identity.${env.DOMAIN}
${env.NODE_IP} backoffice.${env.DOMAIN}
${env.NODE_IP} storefront.${env.DOMAIN}
${env.NODE_IP} grafana.${env.DOMAIN}
${env.NODE_IP} api.${env.DOMAIN}
                        """.trim()
                    
                    echo "=========================================================="
                }
            }
        }
    }
}
