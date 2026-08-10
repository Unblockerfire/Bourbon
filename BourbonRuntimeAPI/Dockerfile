# syntax=docker/dockerfile:1

FROM node:22-slim AS api-deps
WORKDIR /src/BourbonRuntimeAPI
COPY BourbonRuntimeAPI/package*.json ./
RUN npm ci --omit=dev

FROM node:22-slim AS web-deps
WORKDIR /src/BourbonWebsite
COPY BourbonWebsite/package*.json ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

FROM web-deps AS web-builder
COPY BourbonWebsite ./
RUN npm run build

FROM caddy:2.8 AS caddy

FROM node:22-slim AS runner
WORKDIR /app

ENV NODE_ENV=production

COPY --from=caddy /usr/bin/caddy /usr/bin/caddy

COPY --from=api-deps /src/BourbonRuntimeAPI/node_modules ./api/node_modules
COPY BourbonRuntimeAPI/server.js BourbonRuntimeAPI/updates.json ./api/

COPY --from=web-builder /src/BourbonWebsite/.next/standalone ./web
COPY --from=web-builder /src/BourbonWebsite/.next/static ./web/.next/static
COPY --from=web-builder /src/BourbonWebsite/public ./web/public

COPY BourbonRuntimeAPI/Caddyfile ./Caddyfile
COPY BourbonRuntimeAPI/bin/start-services.sh ./start-services.sh
RUN chmod +x ./start-services.sh

EXPOSE 8080

CMD ["./start-services.sh"]
