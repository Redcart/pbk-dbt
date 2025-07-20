import logging
from google.cloud import bigquery
from jinja2 import Template


def get_context(
    project_id: str,
    dataset: str,
    table_stations: str,
    table_capacity: str,
    table_capacity_over_time: str,
    start_date: str,
) -> dict:
    """
    Retrieves the context for Jinja template rendering.

    Returns:
        dict: Context variables including project ID, dataset, and table.
    """
    return {
        "project_id": project_id,
        "dataset": dataset,
        "table_stations": table_stations,
        "table_capacity": table_capacity,
        "table_capacity_over_time": table_capacity,
        "start_date": start_date,
    }


def run_query(
    project_id: str,
    input_dataset: str,
    output_dataset: str,
    output_table: str,
    sql_file: str,
    start_date: str = None,
) -> str:
    """
    Executes a BigQuery SQL query after parsing it with Jinja.

    Args:
        project_id (str): GCP project ID.
        dataset (str): BigQuery dataset name.
        output_table (str): BigQuery table name.
        sql_file (str): Path to the SQL file.
        context (dict): Context variables for Jinja template rendering.

    Returns:
        str: Status code ("200" for success).
    """
    # Read the SQL file
    with open(file=sql_file, mode="r") as file:
        sql_template = file.read()

    # Render the SQL template with the provided context
    context = get_context(
        project_id=project_id,
        dataset=input_dataset,
        table_stations="stations",
        table_capacity="capacity",
        table_capacity_over_time="stations_capacity_over_time",
        start_date=start_date,
    )
    template = Template(sql_template)
    sql_query = template.render(context)

    logging.info(f"Executing query: {sql_query}")

    table_id = f"{project_id}.{output_dataset}.{output_table}"

    job_config = bigquery.QueryJobConfig(
        destination=table_id, write_disposition="WRITE_APPEND"
    )

    bigquery_client = bigquery.Client(project=project_id)
    job = bigquery_client.query(query=sql_query, job_config=job_config)
    job.result()

    logging.info(msg=f"Data written at: {project_id}.{output_dataset}.{output_table}")

    return "200"
