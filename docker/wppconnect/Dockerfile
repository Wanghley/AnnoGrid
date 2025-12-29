# --- Build Stage ---
FROM node:22-alpine AS builder

# Set working directory
WORKDIR /home/node

# Install build dependencies
RUN apk add --no-cache \
    git \
    python3 \
    make \
    g++ \
    chromium \
    nss \
    bash \
    curl \
    ca-certificates \
    fontconfig \
    ttf-freefont

# Clone WPPConnect server
RUN git clone https://github.com/wppconnect-team/wppconnect-server.git app
WORKDIR /home/node/app

# Copy your config
COPY ./config.ts ./src/config.ts

# Install dependencies with extended network timeout
RUN yarn install --frozen-lockfile --network-timeout 600000

# Build the project if needed
# RUN yarn build   # Uncomment if WPPConnect server needs a build step

# --- Runtime Stage ---
FROM node:22-alpine

WORKDIR /home/node/app

# Copy built node_modules and source code from builder
COPY --from=builder /home/node/app /home/node/app

# Set environment variables if needed
ENV NODE_ENV=production \
    CHROMIUM_PATH=/usr/bin/chromium-browser

# Install runtime dependencies
RUN apk add --no-cache chromium nss fontconfig ttf-freefont

# Expose the server port
EXPOSE 21465

# Start the server
CMD ["yarn", "start"]
