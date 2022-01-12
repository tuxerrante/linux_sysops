#!/bin/bash
# Run this with sudo

windows_user_name="alessandro.affinito"

apt-get update
apt-get install -y bash-completion git gnupg software-properties-common curl jq

###KUBECTL
export KUBECONFIG="/mnt/c/Users/${windows_user_name}/.kube/config"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
mv kubectl /usr/local/bin/

### STARSHIP
#   https://starship.rs/config/#kubernetes
sh -c "$(curl -fsSL https://starship.rs/install.sh)"
mkdir -p ~/.config && touch ~/.config/starship.toml

cat <<EOF >> ~/.config/starship.toml
[kubernetes]
format = 'on [⛵ $context \($namespace\)](dimmed green) '
disabled = false
EOF

### HELM
curl -L https://get.helm.sh/helm-v3.7.2-linux-amd64.tar.gz |tar -C /tmp -zxf -
mv /tmp/linux-amd64/helm /usr/local/bin/helm
chmod 0755 /usr/local/bin/helm

### VIM
git clone --depth=1 https://github.com/amix/vimrc.git ~/.vim_runtime
sh ~/.vim_runtime/install_awesome_vimrc.sh

### TERRAFORM
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
apt-get update && sudo apt-get install terraform

### NVM
nvm_latest=$(curl -Ls https://raw.githubusercontent.com/nvm-sh/nvm/master/package.json |jq --raw-output '.version')
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${nvm_latest}/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
nvm install 'lts/*'

### BASHRC
cat <<EOT >>~/.bashrc 
source <(kubectl completion bash)
source <(helm completion bash)

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_complete

complete -C /usr/bin/terraform terraform

alias workspace="cd /mnt/c/Users/${windows_user_name}/workspace/"

eval "$(starship init bash)"
EOT

### DOCKER
echo
echo "> In docker engine go to settings -> resources -> wsl integration -> enable Ubuntu"

echo
