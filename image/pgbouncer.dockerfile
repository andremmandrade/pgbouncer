# Use build arguments to make versions easily configurable.
ARG PGBOUNCER_VERSION=1.24.1
ARG DEBIAN_FRONTEND=noninteractive

# =================================================================
# Build Stage: Compile PgBouncer from source
# =================================================================
FROM alpine:latest AS builder

# Re-declare ARGs for this stage
ARG PGBOUNCER_VERSION

# Install build-time dependencies
RUN apk add -U --no-cache autoconf autoconf-doc automake udns udns-dev curl gcc libc-dev libevent libevent-dev libtool make openssl-dev pkgconfig postgresql-client

# Copy local source, then compile and install PgBouncer
WORKDIR /tmp
# The source tarball is expected to be in a 'resources' directory next to this Dockerfile
COPY resources/pgbouncer-${PGBOUNCER_VERSION}.tar.gz .

RUN tar -xzf pgbouncer-${PGBOUNCER_VERSION}.tar.gz && \
    cd "pgbouncer-${PGBOUNCER_VERSION}" && \
    ./configure --prefix=/usr/local && \
    make && \
    make install

# =================================================================
# Final Stage: Create the minimal production image
# =================================================================
FROM alpine:latest

# Install only the required runtime libraries
RUN apk add -U --no-cache autoconf autoconf-doc automake udns udns-dev curl gcc libc-dev libevent libevent-dev libtool make openssl-dev pkgconfig postgresql-client

# Copy the compiled binary from the builder stage
COPY --from=builder /usr/local/bin/pgbouncer /usr/local/bin/pgbouncer

RUN mkdir -p /etc/pgbouncer /var/run/pgbouncer && \
    chown -R postgres /etc/pgbouncer /var/run/pgbouncer

# Switch to the non-root user
USER postgres

# Expose the default PgBouncer port
EXPOSE 6432

# The entrypoint is the pgbouncer binary. The config file will be passed as an argument from the Kubernetes Deployment.
ENTRYPOINT ["pgbouncer"]