server {
    if ($host = example.com) {
        return 301 https://$host$request_uri;
    }
                        listen 80;
                        listen [::]:80;

                        server_name example.com;
                        return 404;
}

server {
                listen [::]:443 ssl;
                listen 443 ssl;
                server_name example.com;

                # set max upload size
                client_max_body_size 102400M;

location / {
           proxy_pass  http://localhost:80;
           proxy_redirect     off;
           proxy_set_header   Host $host;
           proxy_set_header   X-Real-IP $remote_addr;
           proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header   X-Forwarded-Host $server_name;
           proxy_set_header   X-Forwarded-Proto https;
           proxy_set_header   Upgrade $http_upgrade;
           proxy_set_header   Connection "upgrade";
           proxy_read_timeout 86400;
        }

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}