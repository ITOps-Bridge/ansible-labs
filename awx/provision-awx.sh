#!/bin/bash
set -eux

# 1) Dépendances
echo "Install deps"
sudo apt-get update -y
sudo apt-get install -y curl git jq python3-pip
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 2) Installer k3s
echo "Install k3s"
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 3) AWX Operator via Kustomize
echo "Deploy AWX Operator"
export AWX_OPERATOR_VERSION="2.19.1"

kubectl create ns awx || true
mkdir -p /root/awx
cd /root/awx

cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - github.com/ansible/awx-operator/config/default?ref=${AWX_OPERATOR_VERSION}
images:
  - name: quay.io/ansible/awx-operator
    newTag: ${AWX_OPERATOR_VERSION}
namespace: awx
EOF

kubectl apply -k .

# attendre l'operator
echo "Waiting for awx-operator-controller-manager..."
for i in $(seq 1 60); do
  phase=$(kubectl -n awx get pods -l control-plane=controller-manager -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
  [ "$phase" = "Running" ] && break
  sleep 5
done

# 4) Déployer AWX instance
echo "Deploy AWX instance"
cat > awx.yml <<EOF
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
spec:
  service_type: nodeport
  nodeport_port: 30080
EOF

kubectl apply -n awx -f awx.yml

# attendre awx pods
echo "Waiting for AWX pods..."
for i in $(seq 1 120); do
  ready=$(kubectl -n awx get pods -l app.kubernetes.io/name=awx -o jsonpath='{range .items[*]}{.status.phase}{" "}{end}' 2>/dev/null || true)
  echo "$ready" | grep -qE 'Running|Succeeded' && break
  sleep 5
done

# 5) Afficher mot de passe
echo "Admin password (user: admin):"
for i in $(seq 1 60); do
  if kubectl get secret awx-admin-password -n awx >/dev/null 2>&1; then
    kubectl get secret awx-admin-password -n awx -o jsonpath="{.data.password}" | base64 --decode; echo
    break
  fi
  sleep 5
done

# 6) Afficher service et URL
echo "Service AWX (NodePort):"
kubectl get svc -n awx | grep awx-service || true
NODEPORT=$(kubectl -n awx get svc awx-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo 30080)
echo "Accès UI : http://192.168.56.120:${NODEPORT}"