#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-ebpflogs}"
AWS_REGION="${AWS_REGION:-us-west-2}"
RECREATE="${RECREATE:-false}"

if ! command -v eksctl >/dev/null 2>&1; then
  echo "eksctl is required: https://eksctl.io/installation/"
  exit 1
fi

if [[ "${RECREATE}" == "true" ]] && eksctl get cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "Deleting EKS cluster '${CLUSTER_NAME}'..."
  eksctl delete cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --wait
fi

if eksctl get cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "Cluster '${CLUSTER_NAME}' already exists."
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
else
  echo "Creating EKS cluster '${CLUSTER_NAME}' (~15 min)..."
  eksctl create cluster -f "${ROOT}/eks/cluster.yaml"
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null
fi

kubectl config use-context "$(kubectl config get-contexts -o name | grep "${CLUSTER_NAME}" | head -1)" 2>/dev/null || true

echo "Kube context: $(kubectl config current-context)"
kubectl get nodes -o custom-columns='NAME:.metadata.name,KERNEL:.status.nodeInfo.kernelVersion,OS:.status.nodeInfo.osImage'
