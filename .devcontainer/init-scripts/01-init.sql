\set ON_ERROR_STOP on

-- Development-only application credential; never reuse in production.
SET password_encryption = 'scram-sha-256';

CREATE ROLE citewise_app
  LOGIN
  PASSWORD 'citewise-local-development'
  NOSUPERUSER
  CREATEDB
  NOCREATEROLE
  NOREPLICATION
  NOBYPASSRLS;

CREATE DATABASE citewise_development
  OWNER citewise_app
  TEMPLATE citewise_vector_template;

CREATE DATABASE citewise_development_queue
  OWNER citewise_app;

CREATE DATABASE citewise_development_cable
  OWNER citewise_app;

CREATE DATABASE citewise_test
  OWNER citewise_app
  TEMPLATE citewise_vector_template;

CREATE DATABASE citewise_test_queue
  OWNER citewise_app;

