FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci --no-audit --no-fund ; else npm install --no-audit --no-fund ; fi

COPY . .
RUN npm run build


FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build --chown=nginx:nginx /app/dist /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q --tries=1 --spider http://127.0.0.1:8080/ || exit 1
