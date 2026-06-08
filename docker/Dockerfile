FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
# Use --no-install-recommends to minimize image size
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    jq \
    vim-tiny \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy project files
COPY . /app

# Create Python virtual environment
RUN python -m venv /app/.venv

# Install Python dependencies in virtual environment
# Core dependencies for agent operations
RUN /app/.venv/bin/pip install --upgrade pip && \
    /app/.venv/bin/pip install --no-cache-dir \
    openhands \
    uv \
    httpx \
    aiohttp \
    pytest \
    pytest-asyncio \
    numpy \
    sympy \
    scipy

# Set Python path and virtual environment
ENV PYTHONPATH=/app
ENV VIRTUAL_ENV=/app/.venv
ENV PATH="/app/.venv/bin:$PATH"

# Ollama configuration (connects to host)
ENV OLLAMA_HOST=host.docker.internal:11434
ENV OLLAMA_BASE_URL=http://host.docker.internal:11434

# Default command - activates venv automatically
CMD ["/bin/bash"]