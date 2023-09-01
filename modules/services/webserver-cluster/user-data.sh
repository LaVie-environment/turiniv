#!/bin/bash
sudo apt update -y
sudo apt install nginx -y
cat > index.html <<EOF
<h1>Hello, this is a basic Panta page served by Nginx</h1>
<p>DB address: ${db_address}</p>
<p>DB port: ${db_port}</p>
EOF
sudo service nginx restart
