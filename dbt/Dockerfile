# syntax=docker/dockerfile:1
#
# dbt runtime image. Build from the repository root, because dependencies are locked there:
#
#   docker build -f dbt/Dockerfile -t dataplat-dbt .

FROM python:3.12-slim-bookworm AS build

COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /usr/local/bin/uv

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/opt/venv

WORKDIR /src

# Dependencies first: this layer only changes when a lock file does.
COPY pyproject.toml uv.lock ./
COPY dbt/pyproject.toml dbt/pyproject.toml
COPY tools/datagen/pyproject.toml tools/datagen/pyproject.toml
RUN uv sync --locked --no-dev --package dataplat-dbt

# Packages are installed now, so a running task needs no route to the dbt package hub.
COPY dbt/ dbt/
WORKDIR /src/dbt
RUN /opt/venv/bin/dbt deps --profiles-dir .


FROM python:3.12-slim-bookworm

RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin dbt

COPY --from=build /opt/venv /opt/venv
COPY --from=build --chown=root:root /src/dbt /app/dbt

# The root filesystem is read-only at run time. Everything dbt writes goes to /work, which the
# task definition mounts as a writable volume. The directory exists in the image and belongs to
# the dbt user, so the (initially empty) volume inherits that ownership.
RUN mkdir /work && chown 10001:10001 /work
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HOME=/work/home \
    DBT_PROFILES_DIR=/app/dbt \
    DBT_TARGET_PATH=/work/dbt/target \
    DBT_LOG_PATH=/work/dbt/logs \
    DBT_PACKAGES_INSTALL_PATH=/app/dbt/dbt_packages \
    DBT_SEND_ANONYMOUS_USAGE_STATS=false \
    DBT_TARGET=runtime

WORKDIR /app/dbt
USER 10001

ENTRYPOINT ["python", "/app/dbt/entrypoint.py"]
CMD ["debug"]
