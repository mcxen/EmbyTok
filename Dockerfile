FROM node:20-alpine AS build

WORKDIR /app

COPY package.json ./
RUN npm install --no-audit --no-fund

COPY . .
RUN npm run build

FROM node:20-alpine AS runtime

WORKDIR /app

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=5176 \
    SERVE_WEB=true \
    WEB_ROOT=/app/dist \
    LAN_CONFIG_FILE=/app/data/lan-media-config.json \
    MEDIA_ROOT=/media \
    BROWSE_ROOTS=/media

RUN addgroup -S app && adduser -S app -G app

COPY --from=build /app/dist ./dist
COPY --from=build /app/server ./server

RUN mkdir -p /app/data /media && chown -R app:app /app /media

USER app

EXPOSE 5176

CMD ["node", "server/lan-media-server.mjs"]
