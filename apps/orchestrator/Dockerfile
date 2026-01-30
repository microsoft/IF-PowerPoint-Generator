# Build stage
FROM python:3.11-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Runtime stage
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    fontconfig \
    libfontconfig1 \
    libpango-1.0-0 \
    libcairo2 \
    fonts-dejavu-core \
    fonts-liberation \
    chromium \
    chromium-driver \
    && rm -rf /var/lib/apt/lists/* \
    && fc-cache -f -v

ENV CHROME_BIN=/usr/bin/chromium
ENV CHROMIUM_PATH=/usr/bin/chromium

COPY --from=builder /root/.local /app/.local
  ENV PATH=/app/.local/bin:$PATH
  ENV PYTHONPATH=/app/.local/lib/python3.11/site-packages

COPY src/ ./src/

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]

