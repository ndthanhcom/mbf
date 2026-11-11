# @mbf-vars: DOMAIN ROOT_DIR PHP_VERSION
server {
    listen 80;
    server_name {{DOMAIN}} www.{{DOMAIN}};
    root {{ROOT_DIR}};
    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php/php{{PHP_VERSION}}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
