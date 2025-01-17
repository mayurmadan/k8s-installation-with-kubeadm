#before start script make sure you have 2 cpu and 2 gb ram machine for master/control plane
#!/bin/bash
set -x
# Update and upgrade the system
sudo apt-get update && sudo apt-get upgrade -y

# Load the necessary kernel modules
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set kernel parameters for Kubernetes
sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# Reload system configuration
sudo sysctl --system

# Install required packages
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates

########################################################################################################
#Install containerd run time
sudo apt install -y curl gnupg2 software-properties-common apt-transport-https ca-certificates
####old keys
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --yes --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

sudo apt update
sudo apt install -y containerd.io

# Configure containerd to use systemd as the cgroup driver
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# Restart and enable containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Add Kubernetes repository
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
#curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.27/deb/Release.key | sudo gpg --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

#echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.27/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update

# Install Kubernetes components
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

##Initialize Kubernetes master node
sudo kubeadm init --pod-network-cidr 192.168.0.0/16

# Set up kubeconfig for the regular user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Calico network plugin
curl https://raw.githubusercontent.com/projectcalico/calico/v3.29.1/manifests/calico.yaml -O
#curl https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml -O
kubectl apply -f calico.yaml

# Generate the join command for worker nodes
echo "Use the following command to join worker nodes to the cluster:"
kubeadm token create --print-join-command

# Allow scheduling pods on the master node (optional)
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

#setup autocomplte for k8s
apt-get install bash-completion -y
source /usr/share/bash-completion/bash_completion
echo 'source <(kubectl completion bash)' >>~/.bashrc
source ~/.bashrc

###################3
#k8s init script to start kubectl at every restart
##scirpt to call at each startup
K8S_INIT_SCRIPT="/usr/local/bin/init_k8s.sh"
cat <<EOL > $K8S_INIT_SCRIPT
#!/bin/bash
# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
# Restart kubelet service
sudo systemctl stop kubelet.service
sudo systemctl start kubelet.service
EOL

##service file for k8s init for automatic restart service
init_k8s="[Unit]
Description=Initialize Kubernetes Setup
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/init_k8s.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target"

#create file for systemd
cat >/lib/systemd/system/init_k8s.service <<-EOF
$init_k8s
EOF

#start exeution
sudo chmod 0777 $K8S_INIT_SCRIPT
sleep 0.5
sudo systemctl daemon-reload
sleep 0.5
sudo systemctl enable init_k8s.service
sleep 0.5
sudo systemctl start init_k8s.service
sleep 0.5

##print token again
# Generate the join command for worker nodes
echo "Use the following command to join worker nodes to the cluster:"
kubeadm token create --print-join-command
