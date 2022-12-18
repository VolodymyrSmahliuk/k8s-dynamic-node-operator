#!/bin/bash

help() {
    echo ""
    echo "Usage: $0 -m [init|reset]"
    echo -e "\t-m\tDefine the mode of execution:"
    echo -e "\t\tinit\tInitialize workstation and join it to the cluster."
    echo -e "\t\treset\tClear the system and break up the connection to the cluster."
    exit 1 # Exit script after printing help
}

while getopts "m:" opt; do
    case "$opt" in
    m) mode="$OPTARG" ;;
    ?) help ;; # Print help in case parameter is non-existent
    esac
done

# Print help in case parameters are empty
if [ -z "$mode" ] || [ "$mode" != "init" ] && [ "$mode" != "reset" ]; then
    echo "You must define the mode of execution."
    help
fi

# ----------------------------
# System checks
# ----------------------------

check_run_as_root() {
    # Check if the script is being run as root
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit
    fi
}

define_os() {
    # Define operational system of workstation
    if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        # linuxbase.org
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        # For some versions of Debian/Ubuntu without lsb_release command
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        # Older Debian/Ubuntu/etc.
        OS=Debian
        VER=$(cat /etc/debian_version)
    elif [ -f /etc/SuSe-release ]; then
        # Older SuSE/etc.
        ...
    elif [ -f /etc/redhat-release ]; then
        # Older Red Hat, CentOS, etc.
        ...
    else
        # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    # echo "$OS" "$VER"
    echo "$OS"
}

# ----------------------------
# Runtime components functions
# ----------------------------

check_runtime_components() {
    docker version
}

run_container_runtime() {
    systemctl start docker
}

install_container_runtime() {
    if [ "$1" == "Ubuntu" ]; then
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
    elif [ "$1" == "CentOS Linux" ]; then
        yum install -y yum-utils device-mapper-persistent-data lvm2
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io
    fi

    run_container_runtime
}

delete_container_runtime() {
    if [ "$1" == "Ubuntu" ]; then
        apt-get remove -y docker-ce docker-ce-cli containerd.io
    elif [ "$1" == "CentOS Linux" ]; then
        yum remove -y docker-ce docker-ce-cli containerd.io
    fi
}

# ----------------------------
# Kubernetes components functions
# ----------------------------

install_kubernetes_components() {
    if [ "$1" == "Ubuntu" ]; then
        curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
        cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
        apt-get update
        apt-get install -y kubelet kubeadm kubectl
        apt-mark hold kubelet kubeadm kubectl
    elif [ "$1" == "CentOS Linux" ]; then
        cat <<EOF >/etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
        setenforce 0
        yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
        systemctl enable --now kubelet
    fi
}

delete_kubernetes_components() {
    if [ "$1" == "Ubuntu" ]; then
        apt-get remove -y kubelet kubeadm kubectl
    elif [ "$1" == "CentOS Linux" ]; then
        yum remove -y kubelet kubeadm kubectl
    fi
}

check_kubernetes_components() {
    kubeadm version
    kubelet --version
    kubectl version
}

# ----------------------------
# System preparation functions
# ----------------------------

disabling_swap_memory() {
    swapoff -a
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
}

enabling_swap_memory() {
    swapon -a
}

# ----------------------------

init_mode() {
    echo "Initializing workstation..."
    install_container_runtime "$1"
    install_kubernetes_components "$1"
    disabling_swap_memory
    join_kubernetes_cluster
    check_node_has_joined_cluster
}

reset_mode() {
    echo "Resetting workstation..."
    delete_container_runtime "$1"
    delete_kubernetes_components "$1"
    enabling_swap_memory # TODO: Run only if flag is set
    reset_kubernetes_cluster
}

check_node_has_joined_cluster() {
    echo "Checking if node has joined cluster..."
    kubectl get nodes
}

# ----------------------------
# Kubernetes cluster functions
# ----------------------------

get_kubernetes_cluster_token() {
    echo "Getting Kubernetes cluster token..."
    # TODO:
    # Make a request to the http://cluster.local endpoint.
    discovery_token=$(curl http://cluster.local/token)
    echo "$discovery_token"
}

get_kubernetes_cluster_token_ca_cert_hash() {
    echo "Getting Kubernetes cluster token CA cert hash..."
    # TODO:
    # Make a request to the http://cluster.local endpoint.
    discovery_token_ca_cert_hash=$(curl http://cluster.local/token-ca-cert-hash)
    echo "$discovery_token_ca_cert_hash"
}

join_kubernetes_cluster() {
    echo "Joining Kubernetes cluster..."
    discovery_token=get_kubernetes_cluster_token
    discovery_token_ca_cert_hash=get_kubernetes_cluster_token_ca_cert_hash
    kubeadm join --discovery-token $discovery_token --discovery-token-ca-cert-hash $discovery_token_ca_cert_hash
}

reset_kubernetes_cluster() {
    echo "Resetting connection to Kubernetes cluster..."
    kubeadm reset
}

# ----------------------------

main() {
    check_run_as_root
    os=$(define_os)
    echo "OS: $os"
    if [ "$mode" == "init" ]; then
        init_mode "$os"
    elif [ "$mode" == "reset" ]; then
        reset_mode "$os"
    fi
}

main
