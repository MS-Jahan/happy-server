# Stage 1: Building the application
FROM node:20 AS builder

# Install dependencies
RUN apt-get update && apt-get install -y python3 ffmpeg make g++ build-essential && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package.json and yarn.lock
COPY package.json yarn.lock ./
COPY ./prisma ./prisma

# Configure yarn for environments with SSL interception
# NOTE: This disables strict SSL checking. For production, use proper CA certificates.
RUN yarn config set strict-ssl false

# Install dependencies
# Set NODE_TLS_REJECT_UNAUTHORIZED=0 for Prisma binary downloads
ENV NODE_TLS_REJECT_UNAUTHORIZED=0
RUN yarn install --frozen-lockfile --ignore-engines
ENV NODE_TLS_REJECT_UNAUTHORIZED=1

# Copy the rest of the application code
COPY ./tsconfig.json ./tsconfig.json
COPY ./vitest.config.ts ./vitest.config.ts
COPY ./sources ./sources

# Build the application
RUN yarn build

# Generate Prisma client
RUN yarn prisma generate

# Stage 2: Runtime
FROM node:20 AS runner

WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y python3 ffmpeg && rm -rf /var/lib/apt/lists/*

# Set environment to production
ENV NODE_ENV=production

# Copy necessary files from the builder stage
COPY --from=builder /app/tsconfig.json ./tsconfig.json
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/sources ./sources
COPY --from=builder /app/prisma ./prisma

# Expose the port the app will run on
EXPOSE 3005

# Command to run migrations then start the app
CMD ["sh", "-c", "yarn prisma migrate deploy && yarn start"]
