from pathlib import Path

import runner

JOBS = {
    "refresh": {"name": "refresh", "command": "build", "args": ["--select", "vault"], "schedule": "*/5 * * * *"},
    "full_refresh": {"name": "full_refresh", "command": "build", "args": ["--full-refresh"], "schedule": None},
    "freshness": {"name": "freshness", "command": "source freshness"},
}


def test_build_command():
    assert runner.build_command(JOBS["refresh"], []) == [
        "dbt",
        "--log-format",
        "json",
        "build",
        "--select",
        "vault",
    ]


def test_build_command_appends_extra_args():
    assert runner.build_command(JOBS["full_refresh"], ["--select", "stg_stations+"])[-3:] == [
        "--full-refresh",
        "--select",
        "stg_stations+",
    ]


def test_multi_word_command():
    assert runner.build_command(JOBS["freshness"], [])[3:] == ["source", "freshness"]


def test_schedules_skip_manual_jobs():
    assert runner.schedules(JOBS) == ["refresh\t*/5 * * * *"]


def test_data_product_is_valid():
    jobs = runner.load_jobs(Path(runner.__file__).parent / "data_product.yml")
    assert {"refresh", "full_refresh"} <= set(jobs)
    assert all("command" in job for job in jobs.values())
