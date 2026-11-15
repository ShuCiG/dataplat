FROM apache/airflow:3.4.0-python3.12

# Versions come from Airflow's own constraints file, so the image resolves the way the
# Airflow release was tested. Add packages to requirements.txt, never pin them here.
ARG AIRFLOW_VERSION=3.4.0
ARG PYTHON_VERSION=3.12

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"
