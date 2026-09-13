FROM node:22-alpine
WORKDIR /service/backend
COPY backend/package*.json ./
RUN npm ci --omit=dev --ignore-scripts
COPY backend/src ./src
COPY contracts /service/contracts
USER node
CMD ["node","src/server.js"]
