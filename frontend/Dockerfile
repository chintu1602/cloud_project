# Stage 1: Build React app
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

# Stage 2: Serve with Nginx
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
# Copy template — BACKEND_URL is substituted at container startup via envsubst
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost/ || exit 1
# nginx:alpine official image automatically runs envsubst on /etc/nginx/templates/*.template
# and writes the result to /etc/nginx/conf.d/ before starting nginx.
CMD ["/docker-entrypoint.sh", "nginx", "-g", "daemon off;"]
