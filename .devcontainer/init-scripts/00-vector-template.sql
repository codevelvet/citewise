\set ON_ERROR_STOP on
\connect postgres

CREATE DATABASE citewise_vector_template
  WITH OWNER = postgres
       TEMPLATE = template0
       ENCODING = 'UTF8';

\connect citewise_vector_template

CREATE EXTENSION vector;

-- Prevent ordinary users from modifying the template.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

\connect postgres

ALTER DATABASE citewise_vector_template IS_TEMPLATE true;
ALTER DATABASE citewise_vector_template ALLOW_CONNECTIONS false;
