#!/bin/bash
# Show each command executing
set -x
# Install prerequisites:
# shellcheck disable=SC2164
cd ~
apt update -y
apt upgrade -y
apt install python3-pip -y
apt install git -y


# Install Ansible:
pip install ansible

# Install KubeSpray:
git clone https://github.com/kubernetes-sigs/kubespray.git
# shellcheck disable=SC2164
cd kubespray/
pip install -r requirements.txt

# Install K8s cluster using KubeSpray:
cp -rfp inventory/sample inventory/mycluster
ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -q -N ""
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
ssh-keyscan -H 127.0.0.1 >> ~/.ssh/known_hosts
printf "all:\n  hosts:\n    localhost:\n      ansible_host: 127.0.0.1\n      access_connection: local\n  children:\n    kube_control_plane:\n      hosts:\n        localhost:\n    kube_node:\n      hosts:\n        localhost:\n    etcd:\n      hosts:\n        localhost:\n    k8s_cluster:\n      children:\n        kube_control_plane:\n        kube_node:\n    calico_rr:\n      hosts: {}\n" > inventory/mycluster/hosts.yaml
ansible-playbook -i inventory/mycluster/hosts.yaml  --become --become-user=root cluster.yml

# Install Helm:
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Install Nginx controller (with hostPorts added):
curl https://raw.githubusercontent.com/behniafb/ingress-nginx-with-host-port/main/deploy.yaml > ~/install-nginx-ingress.yaml
kubectl apply -f ~/install-nginx-ingress.yaml

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Install ArgoCD CLI to be able to work with CLI (required in this task, as everything must be automated):
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# Wait until ArgoCD is ready
sleep 30

# Get ArgoCD admin password (in $ARGOCD_PASSWORD):
echo 'export ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)' >> ~/.bashrc

# Set domain name as a variable:
echo 'export DOMAIN=behnia-farahbod-nl-rg2.maxtld.dev' >> ~/.bashrc

# Make ArgoCD accessible from outside & get it's NodePort:
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
echo 'export ARGOCD_ACCESS_PORT=$(kubectl -n argocd get svc argocd-server -o jsonpath="{.spec.ports[0].nodePort}";)' >> ~/.bashrc

# Save these variables:
# shellcheck disable=SC1090
source ~/.bashrc

# Login to argocd CLI:
argocd login $DOMAIN:$ARGOCD_ACCESS_PORT --insecure --username admin --password $ARGOCD_PASSWORD

# Add devops-test repo to ArgoCD
printf "-----BEGIN OPENSSH PRIVATE KEY-----\n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\n-----END OPENSSH PRIVATE KEY-----" > ~/.ssh/github_ssh_key
argocd repo add git@github.com:behniafb/devops-test.git  --insecure-ignore-host-key --ssh-private-key-path ~/.ssh/github_ssh_key

# Pull images (I do because I want deployments to run ASAP):
nerdctl pull wordpress:php8.2-apache
nerdctl pull phpmyadmin/phpmyadmin:latest

### Final steps ###
# Create & run the cluster, in a GitOps manner:
printf "apiVersion: argoproj.io/v1alpha1\nkind: Application\nmetadata:\n  name: task\nspec:\n  destination:\n    name: ''\n    namespace: devops-test\n    server: 'https://kubernetes.default.svc'\n  source:\n    path: task\n    repoURL: 'git@github.com:behniafb/devops-test.git'\n    targetRevision: development\n    helm:\n      valueFiles:\n        - values.yaml\n  sources: []\n  project: default\n  syncPolicy:\n    syncOptions:\n      - CreateNamespace=true\n    automated:\n      prune: true\n      selfHeal: true" > ~/task.yaml
argocd app create -f ~/task.yaml

# Wait for 30s, so the app is deployed. Then continue:
echo 'The app is being deployed...'
sleep 30

## The final step, to make the ingresses route correctly:
# For phpmyadmin
kubectl -n devops-test exec -it deployments/task-phpmyadmin -- mkdir /dbadmin
kubectl -n devops-test exec -it deployments/task-phpmyadmin -- bash -c 'mv /var/www/html/* /dbadmin/'
kubectl -n devops-test exec -it deployments/task-phpmyadmin -- bash -c 'mv /dbadmin /var/www/html/'

# For Wordpress
kubectl -n devops-test exec -it deployments/task-wordpress -- mkdir /wordpress
kubectl -n devops-test exec -it deployments/task-wordpress -- bash -c 'mv /var/www/html/* /wordpress/'
kubectl -n devops-test exec -it deployments/task-wordpress -- bash -c 'mv /wordpress /var/www/html/'

### End of script