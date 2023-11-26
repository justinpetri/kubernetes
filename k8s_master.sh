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
    nfs-kernel-server \
    nfs-common
    

# Write files
sudo bash -c 'cat <<EOF > /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF'
sudo chmod 0644 /etc/docker/daemon.json
sudo chown root:root /etc/docker/daemon.json

sudo bash -c 'cat <<EOF > /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF'
sudo chmod 0644 /etc/sysctl.d/kubernetes.conf
sudo chown root:root /etc/sysctl.d/kubernetes.conf

sudo mkdir -p /home/ubuntu/utils
sudo bash -c 'cat <<EOF > /home/ubuntu/utils/nfs-server.sh
#!/bin/bash
NFS_STORE="/srv/nfs/kube"
LINE="\$NFS_STORE *(rw,sync,subtree_check,no_root_squash,no_all_squash)"
FILE="/etc/exports"
if [ ! -d \$NFS_STORE ]; then
    printf '%s\n' --------------------
    printf "Creating directories...\n"
    printf '%s\n' --------------------
    sudo mkdir -p \$NFS_STORE
    ls -R /srv
    printf '%s\n' --------------------
    printf "Directories created.\n"
    printf '%s\n' --------------------
fi
printf '%s\n' --------------------
printf "Configuring NFS service...\n"
printf '%s\n' --------------------
grep -qF -- "\$LINE" "\$FILE" || echo "\$LINE" | sudo tee -a "\$FILE"
sudo chown nobody:nogroup \$NFS_STORE
sudo exportfs -rav
sudo exportfs -v
printf '%s\n' --------------------
printf "Done.\n"
printf '%s\n' --------------------
printf '%s\n' --------------------
printf "Starting NFS service...\n"
printf '%s\n' --------------------
sudo systemctl daemon-reload
sudo systemctl enable nfs-kernel-server
sudo systemctl restart nfs-kernel-server.service
sudo systemctl status nfs-kernel-server.service
printf '%s\n' --------------------
printf "Done.\n"
printf '%s\n' --------------------
EOF'
sudo chmod 0755 /home/ubuntu/utils/nfs-server.sh

sudo bash -c 'cat <<EOF > /home/ubuntu/utils/post-install.sh
#!/bin/bash
printf '%s\n' --------------------
printf "Starting NFS service...\n"
printf '%s\n' --------------------
sudo systemctl daemon-reload
sudo systemctl enable nfs-kernel-server
sudo systemctl restart nfs-kernel-server.service
sudo systemctl status nfs-kernel-server.service
printf '%s\n' --------------------
printf "Done.\n"
printf '%s\n' --------------------
EOF'
sudo chmod 0755 /home/ubuntu/utils/post-install.sh

# Run commands
sudo systemctl enable docker
sudo systemctl daemon-reload
sudo systemctl restart docker
docker run hello-world
sudo sed -i '/swap/d' /etc/fstab
sudo swapoff -a

sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-yammy main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update

echo "Installing kubectl, kubelet, and kubeadm..."
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


# Disable swap for kubernetes to work properly
sudo swapoff -a


# disabled firewall
systemctl stop ufw


echo "Initializing Kubernetes cluster..."
sudo kubeadm init


# Configure kubectl
mkdir -p $HOME/.kube \
&& sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config \
&& sudo chown $(id -u):$(id -g) $HOME/.kube/config


echo "Installing Calico"
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml


echo "IMPORTANT: SSH into workers and enter the following command:"
kubeadm token create --print-join-command


echo "Installing Metallb"
kubectl get configmap kube-proxy -n kube-system -o yaml | sed -e "s/strictARP: false/strictARP: true/" | kubectl apply -f - -n kube-system
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml

echo "Step 5: Starting NFS Server"
sudo chmod +x /home/ubuntu/utils/nfs-server.sh
/home/ubuntu/utils/nfs-server.sh
sudo chmod +x /home/ubuntu/utils/post-install.sh
/home/ubuntu/utils/post-install.sh

cd ~
git clone https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner.git
cd nfs-subdir-external-provisioner/deploy
sed -i "s/10.3.243.101/$(hostname -I | cut -d " " -f 1)/g" deployment.yaml
sed -i "s+/ifs/kubernetes+/srv/nfs/kube+g" deployment.yaml
kubectl apply -f class.yaml rbac.yaml deployment.yaml
sudo chown -R ubuntu:ubuntu /home/ubuntu
sudo systemctl enable ssh
sudo systemctl start ssh

