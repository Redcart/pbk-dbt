"""Cloud Run Job entry point: run one dbt job declared in data_product.yml.

python runner.py <job> [extra dbt args...]   run the job
python runner.py schedules                   print "<job>\t<cron>" for every scheduled job
"""

import subprocess
import sys
from pathlib import Path

import yaml

DATA_PRODUCT = Path(__file__).parent / "data_product.yml"


def load_jobs(path: Path = DATA_PRODUCT) -> dict[str, dict]:
    return {job["name"]: job for job in yaml.safe_load(path.read_text())["jobs"]}


def build_command(job: dict, extra_args: list[str]) -> list[str]:
    return ["dbt", "--log-format", "json", *job["command"].split(), *job.get("args", []), *extra_args]


def schedules(jobs: dict[str, dict]) -> list[str]:
    return [f"{name}\t{job['schedule']}" for name, job in jobs.items() if job.get("schedule")]


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2

    jobs = load_jobs()
    if argv[0] == "schedules":
        print("\n".join(schedules(jobs)))
        return 0

    if argv[0] not in jobs:
        print(f"unknown job '{argv[0]}', expected one of {sorted(jobs)}", file=sys.stderr)
        return 2

    return subprocess.run(build_command(jobs[argv[0]], argv[1:])).returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
