#!/bin/bash
kubectl create ns application01
kubectl apply -f ./app-infra

echo "Use the following to login to ArgoCD: "
echo "Domain:"
echo " https://argocd.cluster.gijsvandulmen.dev/"
echo "User:"
echo " admin"
echo "Password: "
echo -n " "
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2