from setuptools import setup, find_packages

setup(
    name="claude-usage",
    version="1.0.0",
    packages=find_packages(),
    entry_points={"console_scripts": ["claude-usage=claude_usage.main:main"]},
)
