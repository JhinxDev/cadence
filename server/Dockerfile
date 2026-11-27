FROM python:3.12-slim-bookworm AS builder

WORKDIR /app
RUN pip install --no-cache-dir uv==0.6.14
COPY pyproject.toml ./
COPY src ./src
RUN uv pip install --system --no-cache .

FROM python:3.12-slim-bookworm AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CADENCE_DATA_DIR=/data \
    CADENCE_MUSIC_DIR=/music

RUN groupadd -g 1000 cadence && useradd -u 1000 -g 1000 -m cadence \
    && mkdir -p /data /music /app \
    && chown -R 1000:1000 /data /app

WORKDIR /app
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY src ./src

USER 1000:1000
EXPOSE 4545

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:4545/health', timeout=3)"

CMD ["uvicorn", "cadence.main:app", "--host", "0.0.0.0", "--port", "4545"]
