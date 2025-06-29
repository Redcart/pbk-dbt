import os
from src.utils import run_query

GCP_PROJECT_ID = os.getenv("GCP_PROJECT_ID")
INPUT_DATASET = os.getenv("INPUT_DATASET")
OUTPUT_DATASET = os.getenv("OUTPUT_DATASET")
OUTPUT_TABLE = os.getenv("OUTPUT_TABLE")


def process(requests):
    run_query(
        project_id=GCP_PROJECT_ID,
        input_dataset=INPUT_DATASET,
        output_dataset=OUTPUT_DATASET,
        output_table=OUTPUT_TABLE,
        sql_file="query.sql",
    )

    return "200"


if __name__ == "__main__":
    status = process()
    print(f"Process completed with status: {status}")
