#!/bin/bash

# Add Docker's GPG key and set up repository:
sudo apt update -y

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y


# Install required packages
apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    git \
    nfs-common

# Run commands
sudo sed -i '/swap/d' /etc/fstab
sudo swapoff -a

sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-yammy main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update

echo "Installing kubeadm..."
sudo apt-get update && sudo apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

cd $HOME
# Fix containerd issue when initializing cluster
sudo rm /etc/containerd/config.toml
sudo bash -c 'cat <<EOF > /etc/containerd/config.toml
version = 2
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
EOF'
sudo systemctl restart containerd

sudo kubeadm join 44.47.0.2:6443 --token 1mt6dt.m210n54z1o5trdah --discovery-token-ca-cert-hash sha256:85b8cc8bbad6a91dab56e15290562131667d275f91f273cff3506efd5a506f66
