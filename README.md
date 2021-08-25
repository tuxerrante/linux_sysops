# Linux helpers: scripts and configs

## VBox Ubuntu 
### Packages
```bash
sudo apt update \
&& sudo apt install -y gcc make perl git yamllint curl vim uidmap \
&& curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
&& sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

### Docker rootless
https://docs.docker.com/engine/security/rootless/
```
curl -fsSL https://get.docker.com -o get-docker.sh 
sudo systemctl disable --now docker.service docker.socket
dockerd-rootless-setuptool.sh install
```

### Vim enhances
```
echo <<EOF >>$HOME/.vimrc
set si
set ai
syntax enable
set expandtab
set smarttab
filetype plugin on
filetype indent on
set shiftwidth=2
set tabstop=2
EOF
```  

### Kubernetes 
see [Multipass](https://multipass.run/)
https://medium.com/platformer-blog/kubernetes-multi-node-cluster-with-multipass-on-ubuntu-18-04-desktop-f80b92b1c6a7


