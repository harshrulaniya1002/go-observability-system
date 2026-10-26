#!/bin/bash
# Database initialization script
# This runs automatically when PostgreSQL container starts for the first time
# The POSTGRES_DB environment variable automatically creates the database,
# so this script is mainly for any additional initialization if needed.

set -e

echo "PostgreSQL database initialization completed"

# Add your custom initialization here if needed
# Example: psql -v ON_ERROR_STOP=1 --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" <<-EOSQL
#     -- Your SQL initialization
# EOSQL
