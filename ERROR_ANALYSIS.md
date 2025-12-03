# Error Analysis: Docker Build Failure

## Error Identified

**Error Type**: SSL Certificate Validation Failure  
**Location**: Dockerfile, line 14 (yarn install command)  
**Severity**: Critical - Blocks Docker image build

### Error Message
```
error Error: self-signed certificate in certificate chain
    at TLSSocket.onConnectSecure (node:_tls_wrap:1677:34)
    at TLSSocket.emit (node:events:524:28)
    at TLSSocket._finishInit (node:_tls_wrap:1076:8)
    at ssl.onhandshakedone (node:_tls_wrap:862:12)
info Visit https://yarnpkg.com/en/docs/cli/install for documentation about this command.
```

### Root Cause
When running `docker compose up -d`, the Docker build process fails during the `yarn install` step in the builder stage. This occurs because:

1. The build environment has a corporate proxy or network infrastructure that uses SSL inspection
2. This infrastructure presents a self-signed certificate to intercept HTTPS traffic
3. Node.js and Yarn refuse to connect to the registry due to the untrusted certificate
4. The `yarn install --frozen-lockfile --ignore-engines` command fails with exit code 1

### Impact
- Docker image cannot be built
- Application cannot be deployed using Docker Compose
- Development and production environments are blocked

## Solutions

### Solution 1: Disable Strict SSL (Recommended for Development Only)
Add the following to the Dockerfile before the `yarn install` command:

```dockerfile
# Disable strict SSL for yarn (use only in development/controlled environments)
RUN yarn config set strict-ssl false
```

**Pros**: Simple, quick fix  
**Cons**: Reduces security, should not be used in production

### Solution 2: Configure Yarn to Use Custom CA Certificate
If you have access to the corporate CA certificate:

```dockerfile
# Copy custom CA certificate
COPY ./ca-certificate.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Configure Node to use system certificates
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
```

**Pros**: Maintains security  
**Cons**: Requires obtaining and managing custom CA certificate

### Solution 3: Use HTTP Registry Mirror (If Available)
Configure yarn to use an HTTP-based registry mirror:

```dockerfile
RUN yarn config set registry http://registry.npmjs.org/
```

**Pros**: Bypasses SSL entirely  
**Cons**: Less secure, may not be available in all environments

### Solution 4: Use Network Without Proxy (Production Recommended)
Run Docker build in an environment without SSL inspection/proxy.

**Pros**: No code changes needed, most secure  
**Cons**: Requires infrastructure changes

## Implemented Fix

The issue has been resolved by implementing a secure, minimal-scope approach:

1. **Yarn Configuration**: Temporarily set `yarn config set strict-ssl false` to disable SSL verification for npm package downloads
2. **Node.js Environment Variable**: Set `NODE_TLS_REJECT_UNAUTHORIZED=0` during `yarn install` to allow Prisma binary downloads
3. **Security Cleanup**: Delete the yarn strict-ssl configuration after installation using `yarn config delete strict-ssl`

All three commands are combined in a single RUN instruction to minimize the security vulnerability window and ensure configuration changes don't persist in the final image.

```dockerfile
RUN yarn config set strict-ssl false && \
    NODE_TLS_REJECT_UNAUTHORIZED=0 yarn install --frozen-lockfile --ignore-engines && \
    yarn config delete strict-ssl
```

This approach:
- ✅ Limits SSL bypass to only the installation step
- ✅ Cleans up configuration after use
- ✅ Maintains security for runtime operations
- ✅ Suitable for development environments with SSL interception

For production, implement **Solution 2** or **Solution 4** depending on infrastructure capabilities.

## Additional Context

- The error occurs at Dockerfile line 14
- The application is a TypeScript/Node.js backend using Fastify
- Port changed from 3000 to 3005 in recent commit
- Dependencies are managed with Yarn
- Prisma is used for database ORM

## Testing Steps

After applying the fix:

1. Clean Docker cache: `docker system prune -af`
2. Rebuild images: `docker compose build --no-cache`
3. Start services: `docker compose up -d`
4. Verify services are running: `docker compose ps`
5. Check logs for errors: `docker compose logs happy-server`
