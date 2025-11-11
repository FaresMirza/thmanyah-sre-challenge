
FROM node:20-alpine

WORKDIR /app

ENV NODE_ENV=production

COPY package*.json ./

RUN npm ci --omit=dev

COPY src/ ./src

# Create temp upload directory with proper permissions
RUN mkdir -p /tmp/uploads && chown -R node:node /tmp/uploads

USER node

EXPOSE 3000

CMD ["node", "src/server.js"]