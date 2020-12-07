#!/bin/bash
source 0-config.sh

cd gke-cluster-01
terraform destroy \
    -var="project_id=${PROJECT_ID}" \
    -var="cluster_name=${PROJECT_ID}" \
    -var="region=${REGION}"