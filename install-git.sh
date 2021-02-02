#!/bin/bash

wget https://mirrors.edge.kernel.org/pub/software/scm/git/git-2.9.5.tar.gz

sudo yum install dh-autoreconf curl-devel expat-devel gettext-devel openssl-devel perl-devel zlib-devel asciidoc xmlto docbook2X getopt

sudo ln -s /usr/bin/db2x_docbook2texi /usr/bin/docbook2x-texi

tar -zxf git-2.9.5.tar.gz

cd git-2.9.5

make configure
./configure --prefix=/usr
make all doc info
sudo make install install-doc install-html install-info

