# syntax=docker/dockerfile:1

# ============================================================================
# Multi-stage Dockerfile for Unraid deployment
# Customize the base image and build steps for your application
# ============================================================================

# ----------------------------------------------------------------------------
# Stage 1: Dependencies
# ----------------------------------------------------------------------------
FROM node:20-alpine AS deps

WORKDIR /app

# Install dependencies only (for better layer caching)
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

# ----------------------------------------------------------------------------
# Stage 2: Builder (if you need to compile/build assets)
# ----------------------------------------------------------------------------
FROM node:20-alpine AS builder

WORKDIR /app

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build step (uncomment and customize as needed)
# RUN npm run build

# ----------------------------------------------------------------------------
# Stage 3: Production
# ----------------------------------------------------------------------------
FROM node:20-alpine AS production

# Security: run as non-root user
RUN addgroup --system --gid 1001 appgroup && \
    adduser --system --uid 1001 appuser

WORKDIR /app

# Set production environment
ENV NODE_ENV=production

# Copy only what's needed for production
COPY --from=deps --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --chown=appuser:appgroup . .

# If you have a build step, copy built assets instead:
# COPY --from=builder --chown=appuser:appgroup /app/dist ./dist

# Switch to non-root user
USER appuser

# Expose port (customize as needed)
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Start the application
CMD ["node", "server.js"]
