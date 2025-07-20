import os
import logging
import google.cloud.logging
from src.utils import run_query

# Instantiates a client
client = google.cloud.logging.Client()

# Retrieves a Cloud Logging handler based on the environment
# you're running in and integrates the handler with the
# Python logging module. By default this captures all logs
# at INFO level and higher
client.setup_logging()

GCP_PROJECT_ID = os.getenv("GCP_PROJECT_ID")
INPUT_DATASET = os.getenv("INPUT_DATASET")
OUTPUT_DATASET = os.getenv("OUTPUT_DATASET")


def process(requests):
    """Processes the incoming request to run a BigQuery SQL query.
    Args:
        requests: The incoming request object.
    Returns:
        str: Status code indicating the result of the operation.
    """
    logging.info("Starting capacity over time refresh ...")
    run_query(
        project_id=GCP_PROJECT_ID,
        input_dataset=INPUT_DATASET,
        output_dataset=OUTPUT_DATASET,
        output_table="stations_capacity_over_time",
        sql_file="src/query_bikes_over_time.sql",
    )
    logging.info("capacity over time refresh completed successfully.")

    logging.info("Starting aggregated bikes refresh ...")

    run_query(
        project_id=GCP_PROJECT_ID,
        input_dataset=INPUT_DATASET,
        output_dataset=OUTPUT_DATASET,
        output_table="nb_bikes_aggregated",
        sql_file="src/query_bikes_aggregated.sql",
    )

    logging.info("Aggregated bikes refresh completed successfully.")

    return "200"
