# Linux helpers: scripts and configs

### VBox
#### Ubuntu 
```bash
sudo apt update \
&& sudo apt install -y gcc make perl git yamllint curl \
&& curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
&& sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

