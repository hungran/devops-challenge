FROM node:20-alpine

ENV NODE_ENV=production
WORKDIR /app

# Reproducible installs: lockfile + npm ci, production deps only.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY src ./src

# Don't run as root.
USER node

EXPOSE 3000
CMD ["node", "src/index.js"]
