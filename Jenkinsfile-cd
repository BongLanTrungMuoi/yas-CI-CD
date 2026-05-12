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
        ENV_TAG = "dev-${env.BUILD_ID}"
        YAS_NAMESPACE = "yas-${env.BUILD_ID}"
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
                    echo "Initializing Deployment for ${env.YAS_NAMESPACE}..."
                    
                    def domainOutput = sh(script: "yq -r '.domain' k8s-cd/deploy/cluster-config.yaml", returnStdout: true).trim()
                    if (domainOutput == '__DOMAIN__' || !domainOutput || domainOutput == 'null') {
                        domainOutput = 'yas.local.com'
                    }
                    env.DOMAIN = domainOutput
                    
                    def nodeIp = sh(script: "kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type==\"InternalIP\")].address}'", returnStdout: true).trim()
                    if (!nodeIp) {
                        nodeIp = sh(script: "minikube ip", returnStdout: true).trim()
                    }
                    env.NODE_IP = nodeIp
                }
            }
        }

        stage('Deploy Infrastructure') {
            steps {
                script {
                    echo "Stage 1 & 2: Setting up operators and data layer..."
                    sh """
                        cd k8s-cd/deploy
                        ./01-setup-operators.sh
                        
                        export ENV_TAG=${env.ENV_TAG}
                        export YAS_NAMESPACE=${env.YAS_NAMESPACE}
                        ./02-setup-data-layer.sh
                        sleep(60)
                    """
                }
            }
        }

        stage('Deploy yas-configuration') {
            steps {
                script {
                    sh """
                        cd k8s-cd/charts/yas-configuration
                        helm dependency build .
                        helm upgrade --install yas-configuration . \
                            --namespace ${env.YAS_NAMESPACE} \
                            --set global.domain=${env.DOMAIN} \
                            --set global.envTag=${env.ENV_TAG}
                    """
                }
            }
        }

        stage('Deploy Applications') {
            steps {
                script {
                    def deployService = { serviceName, isUi, extraArgs ->
                        def paramName = serviceName.replace('-', '_')
                        def branchName = params."${paramName}" ?: 'main'
                        def tag = 'latest'

                        if (branchName != 'main' && serviceName != 'swagger-ui') {
                            echo "Fetching tag for ${serviceName} branch ${branchName}"
                            tag = sh(script: "git ls-remote https://github.com/Hownameee/yas.git ${branchName} | cut -f1", returnStdout: true).trim()
                        }

                        def hostPrefix = serviceName.contains('swagger') ? 'api' : serviceName.replace('-bff', '').replace('-ui', '')
                        def host = "${hostPrefix}-${env.ENV_TAG}.${env.DOMAIN}"
                        
                        def imageTagKey = isUi ? 'ui.image.tag' : 'backend.image.tag'
                        def ingressHostKey = isUi ? 'ingress.host' : 'backend.ingress.host'
                        
                        def helmCmd = """
                            cd k8s-cd/charts/${serviceName}
                            helm dependency build .
                            helm upgrade --install ${serviceName} . \
                                --namespace ${env.YAS_NAMESPACE} \
                                --set ${imageTagKey}=${tag} \
                                --set ${ingressHostKey}=${host} \
                                --set global.domain=${env.DOMAIN} \
                                --set global.envTag=${env.ENV_TAG} \
                                ${extraArgs}
                        """
                        sh helmCmd
                    }

                    // Deploy BFFs and UIs
                    deployService('backoffice-bff', false, "")
                    deployService('backoffice-ui', true, "--set ui.extraEnvs[0].name=API_BASE_PATH --set ui.extraEnvs[0].value=http://backoffice-${env.ENV_TAG}.${env.DOMAIN}/api")
                    sleep(20)
                    
                    deployService('storefront-bff', false, "")
                    deployService('storefront-ui', true, "--set ui.extraEnvs[0].name=API_BASE_PATH --set ui.extraEnvs[0].value=http://storefront-${env.ENV_TAG}.${env.DOMAIN}/api")
                    sleep(20)
                    
                    deployService('swagger-ui', false, "")
                    sleep(20)

                    // Deploy Microservices
                    def services = ["cart", "customer", "inventory", "location", "media", "order", "payment", "product", "promotion", "rating", "search", "tax", "recommendation", "webhook", "sampledata"]
                    for (svc in services) {
                        deployService(svc, false, "")
                        sleep(30)
                    }
                }
            }
        }

        stage('Access Information') {
            steps {
                script {
                    def suffix = "-${env.ENV_TAG}.${env.DOMAIN}"
                    echo "=========================================================="
                    echo "DEPLOYMENT COMPLETE - BUILD #${env.BUILD_ID}"
                    echo "=========================================================="
                    echo "IP: ${env.NODE_IP}"
                    echo "----------------------------------------------------------"
                    echo "Copy to /etc/hosts:"
                    echo "${env.NODE_IP} identity${suffix}"
                    echo "${env.NODE_IP} backoffice${suffix}"
                    echo "${env.NODE_IP} storefront${suffix}"
                    echo "${env.NODE_IP} api${suffix}"
                    echo "${env.NODE_IP} pgadmin${suffix}"
                    echo "${env.NODE_IP} akhq${suffix}"
                    echo "${env.NODE_IP} kibana${suffix}"
                    echo "${env.NODE_IP} grafana.${env.DOMAIN}"
                    echo "=========================================================="
                }
            }
        }
    }
}
