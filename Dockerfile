FROM node:20-alpine AS base

# Install dependencies only when needed
FROM base AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
WORKDIR /app

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

COPY package.json pnpm-lock.yaml ./
RUN pnpm i --frozen-lockfile --prefer-offline

# Rebuild the source code only when needed
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
# Force cache invalidation: update this comment when code changes
# Last updated: 2025-12-01
COPY . .

# Next.js collects completely anonymous telemetry data about general usage.
# Learn more here: https://nextjs.org/telemetry
# Uncomment the following line in case you want to disable telemetry during the build.
# ENV NEXT_TELEMETRY_DISABLED 1

ENV NEXT_OUTPUT=standalone
ARG NEXT_PUBLIC_SALEOR_API_URL
ARG NEXT_PUBLIC_STOREFRONT_URL
ARG NEXT_PUBLIC_DEFAULT_CHANNEL
ARG PUBLIC_API_URL

# Get PNPM version from package.json
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

# For GraphQL codegen during build, use public API URL if NEXT_PUBLIC_SALEOR_API_URL points to internal hostname
# Replace internal hostnames with public URL for codegen, then set env vars and build
# PUBLIC_API_URL is passed as build arg from docker-compose.yml (reads from .env file) to avoid hardcoding URLs in public repo
RUN if [ -n "$NEXT_PUBLIC_SALEOR_API_URL" ] && [ -n "$PUBLIC_API_URL" ]; then \
        API_URL_BUILD=$(echo "$NEXT_PUBLIC_SALEOR_API_URL" | \
            sed "s|http://api:8000|${PUBLIC_API_URL}|g" | \
            sed "s|http://dev-saleor-api:8000|${PUBLIC_API_URL}|g" | \
            sed "s|http://api|${PUBLIC_API_URL}|g"); \
        export NEXT_PUBLIC_SALEOR_API_URL="$API_URL_BUILD"; \
    elif [ -n "$NEXT_PUBLIC_SALEOR_API_URL" ]; then \
        echo "Warning: PUBLIC_API_URL not set, graphql-codegen may fail if NEXT_PUBLIC_SALEOR_API_URL points to internal hostname"; \
        export NEXT_PUBLIC_SALEOR_API_URL="$NEXT_PUBLIC_SALEOR_API_URL"; \
    fi && \
    export NEXT_PUBLIC_STOREFRONT_URL="$NEXT_PUBLIC_STOREFRONT_URL" && \
    export NEXT_PUBLIC_DEFAULT_CHANNEL="$NEXT_PUBLIC_DEFAULT_CHANNEL" && \
    pnpm build

# Production image, copy all the files and run next
FROM base AS runner
WORKDIR /app

ENV NODE_ENV production
# Uncomment the following line in case you want to disable telemetry during runtime.
# ENV NEXT_TELEMETRY_DISABLED 1

# Make Next.js listen on all interfaces (required for Docker/Traefik)
ENV HOSTNAME=0.0.0.0
ENV PORT=3000

ARG NEXT_PUBLIC_SALEOR_API_URL
ENV NEXT_PUBLIC_SALEOR_API_URL=${NEXT_PUBLIC_SALEOR_API_URL}
ARG NEXT_PUBLIC_STOREFRONT_URL
ENV NEXT_PUBLIC_STOREFRONT_URL=${NEXT_PUBLIC_STOREFRONT_URL}

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# COPY --from=builder /app/public ./public

# Set the correct permission for prerender cache
RUN mkdir .next
RUN chown nextjs:nodejs .next

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

CMD ["node", "server.js"]
