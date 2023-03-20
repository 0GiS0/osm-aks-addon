# Variables
RESOURCE_GROUP="open-service-mesh-demo"
LOCATION="northeurope"
AKS_NAME="aks-osm-addon"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create AKS cluster with Open Service Mesh enabled
az aks create \
--resource-group $RESOURCE_GROUP \
--name $AKS_NAME \
--node-vm-size Standard_B4ms \
--enable-addons open-service-mesh \
--generate-ssh-keys 

# Get credentials
az aks get-credentials \
--resource-group $RESOURCE_GROUP \
--name $AKS_NAME

# Verify that the OSM add-on is installed on your cluster
az aks show --resource-group $RESOURCE_GROUP --name $AKS_NAME  --query 'addonProfiles.openServiceMesh.enabled'

# You can also verify the version, status, and configuration of the OSM mesh that's running on your cluster.
kubectl get deployment -n kube-system osm-controller -o=jsonpath='{$.spec.template.spec.containers[:1].image}'

# Verify the status od the OSM components running on your cluster
kubectl get deployments -n kube-system --selector app.kubernetes.io/name=openservicemesh.io
kubectl get pods -n kube-system --selector app.kubernetes.io/name=openservicemesh.io
kubectl get services -n kube-system --selector app.kubernetes.io/name=openservicemesh.io

# Verify the configuration of your OSM mesh, use kubectl get meshconfig
kubectl get meshconfig osm-mesh-config -n kube-system -o yaml

##################################
# Deploy demo application in AKS #
##################################

# Deploy manifests in AKS/K8s cluster
kubectl apply -f manifests/.

# Check if the pods are ready
kubectl get pods -n bookstore
kubectl get pods -n bookbuyer
kubectl get pods -n bookthief

# Check if the services are ready
kubectl get services -n bookstore
kubectl get services -n bookbuyer
kubectl get services -n bookthief

# Install osm cli (1.2.3)
# Specify the OSM version that will be leveraged throughout these instructions
OSM_VERSION=v1.2.3
# macOS curl command only
curl -sL "https://github.com/openservicemesh/osm/releases/download/$OSM_VERSION/osm-$OSM_VERSION-darwin-amd64.tar.gz" | tar -vxzf -

# arm
curl -sL "https://github.com/openservicemesh/osm/releases/download/$OSM_VERSION/osm-$OSM_VERSION-darwin-arm64.tar.gz" | tar -vxzf -


# move the osm binary to your PATH
sudo mv ./darwin-amd64/osm /usr/local/bin/osm

# move the osm binary to your PATH - arm
sudo mv ./darwin-arm64/osm /usr/local/bin/osm

osm version

# Now we enable osm for their namespaces
osm namespace add bookstore bookbuyer bookthief

# Check if the namespace has the label openservicemesh.io/monitored-by=osm
kubectl describe ns bookstore

# Check what namespaces are monitored by osm
osm namespace list

# deployment restart
kubectl rollout restart deployment/bookthief -n bookthief
kubectl rollout restart deployment/bookbuyer -n bookbuyer
kubectl rollout restart deployment/bookstore -n bookstore

# Now you have two container instead of one per each pod
kubectl get pods -n bookstore
kubectl get pods -n bookbuyer
kubectl get pods -n bookthief

kubectl describe pod -n bookstore

# We lost access from outside. We have to configure a Ingress Controller

# Configure nginx ingress controller
kubectl create ns ingress-nginx
# osm needs to monitor this namespace but not inject the sidecar
osm namespace add ingress-nginx --disable-sidecar-injection
# add ingress nginx helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install nginx-ingress ingress-nginx/ingress-nginx \
 --namespace ingress-nginx \
 --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

# Get nginx ingress controller public IP
INGRESS_PUBLIC_IP=$(kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
NGINX_INGRESS_NS=ingress-nginx # replace <nginx-namespace> with the namespace where Nginx is installed
NGINX_INGRESS_SVC=nginx-ingress-ingress-nginx-controller  # replace <nginx-ingress-controller-service> with the name of the nginx ingress controller service

#### Bookstore ingress and ingress backend ####

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

---
kind: IngressBackend
apiVersion: policy.openservicemesh.io/v1alpha1
metadata:
  name: bookstore-external-access
  namespace: bookstore
spec:
  backends:
    - name: bookstore
      port:
        number: 3000 # targetPort of the service
        protocol: http
  sources:
    - kind: Service
      name: $NGINX_INGRESS_SVC
      namespace: $NGINX_INGRESS_NS
EOF


#### Bookbuyer ingress and ingress backend ####

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

---
kind: IngressBackend
apiVersion: policy.openservicemesh.io/v1alpha1
metadata:
  name: bookbuyer-external-access
  namespace: bookbuyer
spec:
  backends:
    - name: bookbuyer
      port:
        number: 4000 # targetPort of the service
        protocol: http
  sources:
    - kind: Service
      name: $NGINX_INGRESS_SVC
      namespace: $NGINX_INGRESS_NS

EOF


#### Bookthief ingress and ingress backend ####

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bookthief-ingress
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

---
kind: IngressBackend
apiVersion: policy.openservicemesh.io/v1alpha1
metadata:
  name: bookthief-external-access
  namespace: bookthief
spec:
  backends:
    - name: bookthief
      port:
        number: 4001 # targetPort of the service
        protocol: http
  sources:
    - kind: Service
      name: $NGINX_INGRESS_SVC
      namespace: $NGINX_INGRESS_NS

EOF

kubectl get ingressbackend -n bookstore
kubectl describe ingressbackend -n bookstore

kubectl get ingress --all-namespaces

osm verify ingress --from-service $NGINX_INGRESS_NS/$NGINX_INGRESS_SVC \
--to-pod bookthief/$(kubectl get pod ) \
--to-service bookthief \
--ingress-backend bookthief-external-access --to-port 4001 \
--osm-namespace kube-system

osm verify ingress --from-service ingress-nginx/osm-nginx-ingess-ingress-nginx-controller \
--to-pod bookstore/bookstore-56bcf44d57-njjqv \
--to-service bookstore/bookstore \
--ingress-backend bookstore-external-access --to-port 3000 \
--osm-namespace kube-system

# Now you can access using this URLs
cat <<EOF

http://$INGRESS_PUBLIC_IP/bookstore
http://$INGRESS_PUBLIC_IP/bookbuyer
http://$INGRESS_PUBLIC_IP/bookthief

EOF

# Check errors
kubectl logs -n kube-system $(kubectl get pod -n kube-system -l app=osm-controller -o jsonpath='{.items[0].metadata.name}') | grep error

# Check permissive mode
kubectl get meshconfig osm-mesh-config -n kube-system -o jsonpath='{.spec.traffic.enablePermissiveTrafficPolicyMode}{"\n"}'

# Change to permissive mode to false
kubectl patch meshconfig osm-mesh-config -n kube-system -p '{"spec":{"traffic":{"enablePermissiveTrafficPolicyMode":false}}}'  --type=merge

# Now you need to create traffic policies
kubectl apply -f traffic-access/.
