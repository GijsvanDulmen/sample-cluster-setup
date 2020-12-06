#!/bin/bash
source 0-config.sh

# config
gcloud config set account ${ACCOUNT}
gcloud config set project ${PROJECT_ID}

# enable needed services
gcloud services enable storage-api.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable iam.googleapis.com

# setup cluster with terraform
cd gke-cluster-01

terraform init

terraform validate

terraform apply \
    -var="project_id=${PROJECT_ID}" \
    -var="cluster_name=${PROJECT_ID}" \
    -var="region=${REGION}" \
    -var='network="gke-network"' \
    -var='subnetwork="gke-subnetwork"'

# set correct credentials
gcloud container clusters get-credentials ${PROJECT_ID} --region ${REGION}

# set cluster admin role to current user
kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole cluster-admin \
    --user $(gcloud config get-value account)

# install cert-manager
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.1.0/cert-manager.yaml

# wait for it to be installed
kubectl wait --for=condition=available --timeout=600s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=available --timeout=600s deployment/cert-manager-cainjector -n cert-manager
kubectl wait --for=condition=available --timeout=600s deployment/cert-manager-webhook -n cert-manager

# install argocd
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# wait for it to be installed
kubectl wait --for=condition=available --timeout=600s deployment/argocd-application-controller -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-dex-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-redis -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

# install ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.41.2/deploy/static/provider/cloud/deploy.yaml

# Wait till it's ready
kubectl wait --namespace ingress-nginx \
  --for=condition=available deployment/ingress-nginx-controller \
  --timeout=120s

# install kubernetes ExternalDNS with Google Cloud DNS enabled
CLOUD_DNS_SA=cloud-dns-admin
gcloud --project ${PROJECT_ID} iam service-accounts \
    create ${CLOUD_DNS_SA} \
    --display-name "Service Account for ExternalDNS."

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member serviceAccount:${CLOUD_DNS_SA}@${PROJECT_ID}.iam.gserviceaccount.com \
    --role roles/dns.admin

gcloud iam service-accounts keys create ./external-dns-key.json \
    --iam-account=${CLOUD_DNS_SA}@${PROJECT_ID}.iam.gserviceaccount.com

# create ns
kubectl create ns externaldns

kubectl create secret -n externaldns generic cloud-dns-key \
    --from-file=key.json=./external-dns-key.json

rm ./external-dns-key.json # delete the key again

kubectl apply -n externaldns -f ../cluster-infra/external-dns.yml