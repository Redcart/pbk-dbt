import os
from src.utils import run_query

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
    run_query(
        project_id=GCP_PROJECT_ID,
        input_dataset=INPUT_DATASET,
        output_dataset=OUTPUT_DATASET,
        output_table="stations_capacity_over_time",
        sql_file="src/query_bikes_over_time.sql",
    )

    run_query(
        project_id=GCP_PROJECT_ID,
        input_dataset=INPUT_DATASET,
        output_dataset=OUTPUT_DATASET,
        output_table="nb_bikes_aggregated",
        sql_file="src/query_bikes_aggregated.sql",
    )

    return "200"
