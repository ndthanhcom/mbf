# @mbf-vars: DOMAIN ROOT_DIR
server {
    listen 80;
    server_name {{DOMAIN}} www.{{DOMAIN}};
    root {{ROOT_DIR}};
    index index.html index.htm;

    location / {
        try_files $uri $uri/ =404;
    }
}
