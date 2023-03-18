# Variables
RESOURCE_GROUP="open-service-mesh-demo"
LOCATION="westeurope"
AKS_NAME="aks-osm"

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

#############################
# Deploy Sample application #
#############################

# Generate Docker images
docker build -t 0gis0/bookstore bookstore/.
docker build -t 0gis0/bookbuyer bookbuyer/.
docker build -t 0gis0/bookthief bookthief/.

docker images

# Try to execute the app in Docker
# Create a network for the containers
docker network create bookstore-net

# Create the containers
docker run -d --name bookstore -p 8080:3000 --network bookstore-net 0gis0/bookstore 
docker run -d --name bookbuyer -p 8081:4000 --network bookstore-net 0gis0/bookbuyer
docker run -d --name bookthief -p 8082:4001 --network bookstore-net 0gis0/bookthief

##################################
# Deploy this application in AKS #
##################################

# Publish images in Docker Hub
docker push 0gis0/bookstore
docker push 0gis0/bookbuyer
docker push 0gis0/bookthief

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

# move the osm binary to your PATH
sudo mv ./darwin-amd64/osm /usr/local/bin/osm

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
# osm namespace add ingress-nginx
osm namespace add ingress-nginx
# add ingress nginx helm repo
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install osm-nginx-ingess ingress-nginx/ingress-nginx --namespace ingress-nginx

# Get nginx ingress controller public IP
INGRESS_PUBLIC_IP=$(kubectl get svc -n ingress-nginx osm-nginx-ingess-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Create a ingress rules and ingress backends
kubectl apply -f ingress/.

kubectl get ingressbackend -n bookstore
kubectl describe ingressbackend -n bookstore

# Now you can access using this URLs
cat <<EOF
http://bookstore.$INGRESS_PUBLIC_IP.nip.io/
http://bookbuyer.$INGRESS_PUBLIC_IP.nip.io/
http://bookthief.$INGRESS_PUBLIC_IP.nip.io/

EOF

# Check permissive mode
kubectl get meshconfig osm-mesh-config -n kube-system -o jsonpath='{.spec.traffic.enablePermissiveTrafficPolicyMode}{"\n"}'

# Change to permissive mode to false
kubectl patch meshconfig osm-mesh-config -n kube-system -p '{"spec":{"traffic":{"enablePermissiveTrafficPolicyMode":false}}}'  --type=merge

# Now you need to create traffic policies
kubectl apply -f traffic-access/.
