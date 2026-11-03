FROM node:24-bookworm-slim AS build
# Build from repository root: docker build -f web/Dockerfile .
WORKDIR /app
COPY . .
RUN npm ci && npm run build

FROM node:24-bookworm-slim
ENV NODE_ENV=production PORT=3000
WORKDIR /app
COPY --from=build --chown=node:node /app /app
USER node
EXPOSE 3000
CMD ["node","node_modules/next/dist/bin/next","start","web","-H","0.0.0.0","-p","3000"]
