# Linux helpers: scripts and configs

### VBox
#### Ubuntu 
```bash
sudo apt update \
&& sudo apt install -y gcc make perl git yamllint curl vim \
&& curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
&& sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```
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

