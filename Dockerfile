# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization
# ═══════════════════════════════════════════════════════════════════

# Stage 1: builder (cài dependencies)
FROM python:3.11-slim AS builder

WORKDIR /app

# COPY requirements.txt riêng để tận dụng layer cache của Docker
COPY requirements.txt .
RUN pip install --no-cache-dir --default-timeout=100 -r requirements.txt

# Stage 2: runtime (image gọn nhẹ chỉ chứa app và dependencies)
FROM python:3.11-slim AS runtime

WORKDIR /app

# Tạo user thường (non-root) để bảo mật container
RUN useradd -m -u 5678 appuser

# Copy thư viện và binary đã cài từ builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy source code vào image
COPY . /app

# Gán quyền sở hữu thư mục cho appuser
RUN chown -R appuser:appuser /app

# Chuyển sang user non-root
USER appuser

EXPOSE 8000

# Health check định kỳ gọi endpoint /health bằng python tích hợp sẵn
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Đọc cổng từ biến môi trường PORT (mặc định 8000)
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]