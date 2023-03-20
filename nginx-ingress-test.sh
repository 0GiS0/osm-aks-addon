# Variables
RESOURCE_GROUP="nginx-ingress-demo"
LOCATION="northeurope"
AKS_NAME="aks-with-nginx-ingress"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create AKS cluster with Open Service Mesh enabled
az aks create \
--resource-group $RESOURCE_GROUP \
--name $AKS_NAME \
--node-vm-size Standard_B4ms \
--generate-ssh-keys 

# Get credentials
az aks get-credentials \
--resource-group $RESOURCE_GROUP \
--name $AKS_NAME

# Deploy apps in AKS
kubectl apply -f ./manifests/

# Deploy nginx ingress controller with helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

kubectl create namespace nginx-ingress
helm install nginx-ingress ingress-nginx/ingress-nginx \
 --namespace nginx-ingress \
 --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz


# Verify the status of the nginx ingress controller
kubectl get pods -n nginx-ingress

# Get ngux ingress controller public IP
INGRESS_PUBLIC_IP=$(kubectl get svc -n nginx-ingress nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Check the load balancer service
kubectl get services --namespace nginx-ingress -o wide -w  nginx-ingress-ingress-nginx-controller


# Create Ingress for the apps

#### Bookstore ingress  ####
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bookstore-ingress
  namespace: bookstore
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
    - host: bookstore.$INGRESS_PUBLIC_IP.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: bookstore
                port:
                  number: 80
EOF

kubectl get ingress -n bookstore


#### Bookbuyer ingress ####
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: osm-ingress
  namespace: bookbuyer
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
    - host: bookbuyer.$INGRESS_PUBLIC_IP.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: bookbuyer
                port:
                  number: 80
EOF

#### Bookthief ingress ####
kubectl apply -f - <<EOF

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: osm-ingress
  namespace: bookthief
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: bookthief.$INGRESS_PUBLIC_IP.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: bookthief
                port:
                  number: 80
EOF