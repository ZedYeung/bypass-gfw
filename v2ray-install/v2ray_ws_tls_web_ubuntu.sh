#!/bin/bash
# from https://github.com/atrandys
#ubuntu only
if cat /etc/issue | grep -Eqi "ubuntu"; then
  echo "release is ubuntu"
else
  echo "only support ubuntu"
  exit
fi

function blue(){
    echo -e "\033[34m\033[01m $1 \033[0m"
}
function green(){
    echo -e "\033[32m\033[01m $1 \033[0m"
}
function red(){
    echo -e "\033[31m\033[01m $1 \033[0m"
}
function yellow(){
    echo -e "\033[33m\033[01m $1 \033[0m"
}

# v2ray uuid
v2uuid=$(cat /proc/sys/kernel/random/uuid)

# get path for websocket and update nginx config
v2path=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

install_nginx(){
    green "install nginx"
#    green "====编译安装nginx耗时时间较长，请耐心等待===="
    sleep 1
#    systemctl stop ufw
#    systemctl disable ufw
    apt-get update
    apt -y install nginx nginx-common nginx-full wget unzip zip curl tar
    systemctl enable nginx.service

#    mkdir /etc/nginx
#    mkdir /etc/nginx/conf
#    mkdir /etc/nginx/conf.d
    mkdir /etc/nginx/ssl
    mkdir /etc/nginx/logs

    green "====输入解析到此VPS的域名===="
    read domain

    green "====Please input port for v2ray(port for proxy)===="
    read v2port

    green "===Please input the html file URL for your website==="
    green "e.g. https://gist.githubusercontent.com/User/xxxxxx/raw/xxxxxx/index.html"
    read website

green "initial nginx configuration"

cat > /etc/nginx/nginx.conf <<-EOF
user  root;
worker_processes  1;
error_log  /etc/nginx/logs/error.log warn;
pid        /var/run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log  /etc/nginx/logs/access.log  main;
    sendfile        on;
    #tcp_nopush     on;
    keepalive_timeout  120;
    client_max_body_size 20m;
    #gzip  on;
    include /etc/nginx/conf.d/*.conf;
}
EOF

cat > /etc/nginx/conf.d/default.conf<<-EOF
server {
    listen       80;
    server_name  $domain;
    root /usr/share/nginx/html;
    index index.php index.html index.htm;
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
      root /usr/share/nginx/html;
    }
}
EOF

green "setup website"
rm -rf /usr/share/nginx/html/*
cd /usr/share/nginx/html/
wget $website

systemctl restart nginx.service

if [ $(systemctl is-active nginx.service) = 'failed' ]; then
  red "nginx fialed to restart"
  exit 1
else
  green "restarted nginx"
fi

green "test port 80 is open for domain"
curl -IkL -m20 http://$domain

green "get webroot folder"
ls /usr/share/nginx/html/

green "apply https certs"
curl https://get.acme.sh | sh
	~/.acme.sh/acme.sh  --issue  -d $domain  --webroot /usr/share/nginx/html/
    	~/.acme.sh/acme.sh  --installcert  -d  $domain  \
        --key-file   /etc/nginx/ssl/$domain.key \
        --fullchain-file /etc/nginx/ssl/fullchain.cer \
        --reloadcmd  "systemctl force-reload nginx.service"

green "update nginx configuration"
cat > /etc/nginx/conf.d/default.conf<<-EOF
server {
    listen       80;
    server_name  $domain;
    rewrite ^(.*)$  https://\$host\$1 permanent;
}
server {
    listen 443 ssl http2;
    server_name $domain;
    root /usr/share/nginx/html;
    index index.php index.html;
    ssl_certificate /etc/nginx/ssl/fullchain.cer;
    ssl_certificate_key /etc/nginx/ssl/${domain}.key;
    #TLS 版本控制
    ssl_protocols   TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_ciphers     'TLS13-AES-256-GCM-SHA384:TLS13-CHACHA20-POLY1305-SHA256:TLS13-AES-128-GCM-SHA256:TLS13-AES-128-CCM-8-SHA256:TLS13-AES-128-CCM-SHA256:EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+ECDSA+AES128:EECDH+aRSA+AES128:RSA+AES128:EECDH+ECDSA+AES256:EECDH+aRSA+AES256:RSA+AES256:EECDH+ECDSA+3DES:EECDH+aRSA+3DES:RSA+3DES:!MD5';
    ssl_prefer_server_ciphers   on;
    # 开启 1.3 0-RTT
#    ssl_early_data  on;
#    ssl_stapling on;
#    ssl_stapling_verify on;
    #add_header Strict-Transport-Security "max-age=31536000";
    #access_log /var/log/nginx/access.log combined;
    location /${v2path} {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${v2port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
    location / {
       try_files \$uri \$uri/ /index.php?\$args;
    }
}
EOF

systemctl restart nginx.service
if [ $(systemctl is-active nginx.service) = 'failed' ]; then
  red "nginx fialed to restart"
  exit 1
else
  green "restarted nginx"
fi
}

install_v2ray(){
    green "install v2ray"

    bash <(curl -L -s https://install.direct/go.sh)
    cd /etc/v2ray/
    rm -f config.json

#    ufw allow "${v2port}"
green "config v2ray"
cat > /etc/v2ray/config.json<<-EOF
{
  "log" : {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${v2port},
      "listen":"127.0.0.1",//只监听 127.0.0.1，避免除本机外的机器探测到开放了 10000 端口
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${v2uuid}",
            "alterId": 64
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/${v2path}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

#    sed -i "s/mypath/v2path/;" /etc/nginx/conf.d/default.conf
#    systemctl force-reload  nginx.service
    systemctl enable v2ray.service
    systemctl restart v2ray.service

cat > /etc/v2ray/client-config.json <<EOF
{
  "inbounds": [
    {
      "port": ${v2port},
      "listen": "127.0.0.1",
      "protocol": "socks",
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "settings": {
        "auth": "noauth",
        "udp": false
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "${domain}",
            "port": 443,
            "users": [
              {
                "id": "${v2uuid}",
                "alterId": 64
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "wsSettings": {
          "path": "/${v2path}"
        }
      }
    }
  ]
}
EOF

cat > /etc/v2ray/myconfig.json<<-EOF
{
===========配置参数=============
地址：${domain}
端口：443
v2ray port: ${v2port}
uuid：${v2uuid}
额外id：64
传输协议：ws
路径：${v2path}
底层传输：tls
client config: /etc/v2ray/client-config.json
}
EOF

clear
green
green "安装已经完成"
green
green "===========配置参数============"
green "地址：${domain}"
green "端口：443"
green "v2ray port: ${v2port}"
green "uuid：${v2uuid}"
green "额外id：64"
green "传输协议：ws"
green "路径：${v2path}"
green "底层传输：tls"
green "client config: /etc/v2ray/client-config.json"
green
}

remove_v2ray(){

    systemctl stop nginx.service
    systemctl disable nginx.service
    systemctl stop v2ray.service
    systemctl disable v2ray.service

    apt -y remove nginx nginx-common nginx-full
    apt -y purge nginx-common nginx-full
    apt -y autoremove

    rm -rf /usr/bin/v2ray /etc/v2ray
    rm -rf /etc/v2ray
    rm -rf /etc/nginx

    rm -rf ~/.acme.sh

    crontab -l | grep -v 'acme.sh' | crontab -
    green "nginx、v2ray acme已删除"
}

start_menu(){
    clear
    green " ===================================="
    green " 介绍：一键安装v2ray+ws+tls1.3        "
    green " 系统：ubuntu                       "
    green " 作者：zedyeung                      "
    green " 网站：https://github.com/ZedYeung            "
    green " ===================================="
    echo
    green " 1. 安装v2ray+ws+tls1.3"
    green " 2. 升级v2ray"
    red " 3. 卸载v2ray"
    yellow " 0. 退出脚本"
    echo
    read -p "请输入数字:" num
    case "$num" in
    1)
    install_nginx
    install_v2ray
    ;;
    2)
    bash <(curl -L -s https://install.direct/go.sh)
    ;;
    3)
    remove_v2ray
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    red "请输入正确数字"
    sleep 2s
    start_menu
    ;;
    esac
}

start_menu