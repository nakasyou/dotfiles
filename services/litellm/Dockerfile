# Custom LiteLLM image with xAI OAuth provider from PR #29866
# https://github.com/BerriAI/litellm/pull/29866
FROM python:3.13-slim-bookworm

# System dependencies (git for clone, build deps for some packages)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Clone the PR so we have the schema.prisma and full source
WORKDIR /tmp
RUN git clone --depth 1 https://github.com/BerriAI/litellm.git litellm-src \
    && cd litellm-src \
    && git fetch origin pull/29866/head:pr-29866 \
    && git checkout pr-29866

# Install from the cloned source (ensures PR code + schema is present)
WORKDIR /tmp/litellm-src
RUN pip install --no-cache-dir ".[proxy]"

# Install and generate Prisma client using the schema from source
RUN pip install --no-cache-dir prisma
RUN prisma generate --schema /tmp/litellm-src/schema.prisma

# Clean up source to keep image smaller (optional)
RUN rm -rf /tmp/litellm-src

# Default workdir
WORKDIR /app

# Default command (overridden by compose)
ENTRYPOINT ["litellm"]
CMD ["--config", "/app/config.yaml", "--port", "4000"]
