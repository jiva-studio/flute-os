from setuptools import setup, find_packages

setup(
    name="ai-usage",
    version="2.0.0",
    packages=find_packages(),
    entry_points={"console_scripts": ["ai-usage=ai_usage.main:main"]},
)
