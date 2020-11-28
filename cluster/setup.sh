#!/bin/bash
PROJECT_ID=cluster-test-02
ACCOUNT=gijsvandulmen@gmail.com

# config
gcloud config set account ${ACCOUNT}
gcloud config set project ${PROJECT_ID}

# enable services
gcloud services enable storage-api.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable iam.googleapis.com

# setup service account
gcloud iam service-accounts create terraform
gcloud projects add-iam-policy-binding ${PROJECT_ID} --member "serviceAccount:terraform@${PROJECT_ID}.iam.gserviceaccount.com" --role "roles/owner"
gcloud iam service-accounts keys create key.json --iam-account terraform@${PROJECT_ID}.iam.gserviceaccount.com
export GOOGLE_APPLICATION_CREDENTIALS="$PWD/key.json"

# setup terraform gcs bucket for state share
REGION="europe-west4" # Eemshaven, Netherlands, Europe
BUCKET_NAME="${PROJECT_ID}-terraform-cluster-state"
gsutil mb -l ${REGION} gs://${BUCKET_NAME}
gsutil iam ch serviceAccount:terraform@${PROJECT_ID}.iam.gserviceaccount.com:objectAdmin gs://${BUCKET_NAME}

terraform init -backend-config=bucket=${BUCKET_NAME}

terraform validate

terraform apply \
    -var="gcp_project_id=${PROJECT_ID}" \
    -var="cluster_name=${PROJECT_ID}" \
    -var="identity_namespace=${PROJECT_ID}.svc.id.goog"

# set correct credentials
gcloud container clusters get-credentials ${PROJECT_ID}

# set cluster admin role to current user
kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole cluster-admin \
    --user $(gcloud config get-value account)

# set extra firewall rule for admission webhooks
gcloud compute firewall-rules create allow-admission-webhooks-node1 \
    --action ALLOW \
    --direction INGRESS \
    --source-ranges 172.16.0.0/28 \
    --network vpc-network \
    --rules tcp:8443 \
    --target-tags `gcloud compute firewall-rules list --filter "name~^gke-${PROJECT_ID}" --limit=1 --format=json | jq -r '.[0].targetTags[0]'`

# list
gcloud compute firewall-rules list \
    --format 'table(
        name,
        network,
        direction,
        sourceRanges.list():label=SRC_RANGES,
        allowed[].map().firewall_rule().list():label=ALLOW,
        targetTags.list():label=TARGET_TAGS
    )'

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
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# install domain
echo "Configure the following for the test02.ziny.nl domain: "
kubectl get service -n ingress-nginx ingress-nginx-controller -o json | jq -r '.status.loadBalancer.ingress[0].ip'