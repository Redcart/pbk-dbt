FROM python:3.14-slim

COPY --from=ghcr.io/astral-sh/uv:0.12.18 /uv /usr/local/bin/uv

WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH" DBT_PROFILES_DIR=/app

COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --frozen --no-dev --no-install-project

COPY dbt_project.yml profiles.yml data_product.yml runner.py ./
COPY macros ./macros
COPY models ./models
COPY tests ./tests

# Cloud Run Job: the container args are the job name (see data_product.yml), set per Cloud Scheduler run
ENTRYPOINT ["python", "runner.py"]
