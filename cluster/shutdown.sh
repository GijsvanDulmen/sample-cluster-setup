#!/bin/bash
PROJECT_ID=cluster-test-02

terraform destroy \
    -var="gcp_project_id=${PROJECT_ID}" \
    -var="cluster_name=${PROJECT_ID}"
