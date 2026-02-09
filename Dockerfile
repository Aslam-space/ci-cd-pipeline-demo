FROM nginx:alpine

# Remove default HTML
RUN rm -rf /usr/share/nginx/html/*

# Copy your website files
COPY . /usr/share/nginx/html/

# Copy your custom nginx config
COPY app/nginx /etc/nginx/conf.d/default.conf
~
~
~
~
~
~
~
~
~

