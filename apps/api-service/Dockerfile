
FROM node:20-alpine

ENV NODE_ENV=production

COPY package*.json ./

RUN npm ci --omit=dev

COPY src/ ./src

USER node

EXPOSE 3000

CMD ["node", "src/server.js"]