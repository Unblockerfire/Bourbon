FROM node:20-slim

WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY server.js updates.json ./

ENV NODE_ENV=production

CMD ["npm", "start"]
