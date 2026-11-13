-- One-off account bootstrap. Run once as ACCOUNTADMIN in a Snowsight worksheet ("Run All").
-- Safe to re-run: every statement is idempotent.
--
-- It creates the minimum needed for Terraform to take over:
--   * PLATFORM_ADMIN, the role Terraform works with
--   * a spending cap for the whole account
--   * service users for Terraform that authenticate with workload identity, so there is
--     no password or key to store anywhere
--
-- Replace the two placeholders before running:
--   <AWS_ACCOUNT_ID>        12-digit AWS account id
--   <OIDC_SUBJECT_PREFIX>   gh api repos/<owner>/<repo>/actions/oidc/customization/sub -q .sub_claim_prefix

USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------------------------
-- Role for infrastructure management. ACCOUNTADMIN is not used again after this script.
-- ---------------------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS PLATFORM_ADMIN
  COMMENT = 'Manages databases, warehouses, roles, users and integrations through Terraform.';

GRANT ROLE PLATFORM_ADMIN TO ROLE SYSADMIN;

GRANT CREATE DATABASE    ON ACCOUNT TO ROLE PLATFORM_ADMIN;
GRANT CREATE WAREHOUSE   ON ACCOUNT TO ROLE PLATFORM_ADMIN;
GRANT CREATE ROLE        ON ACCOUNT TO ROLE PLATFORM_ADMIN;
GRANT CREATE USER        ON ACCOUNT TO ROLE PLATFORM_ADMIN;
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE PLATFORM_ADMIN;
GRANT MANAGE GRANTS      ON ACCOUNT TO ROLE PLATFORM_ADMIN;

-- ---------------------------------------------------------------------------------------
-- Spending cap. Warehouses are suspended when the monthly quota is used up.
-- ---------------------------------------------------------------------------------------
CREATE RESOURCE MONITOR IF NOT EXISTS DATAPLAT_ACCOUNT
  WITH CREDIT_QUOTA = 40
       FREQUENCY = MONTHLY
       START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75  PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND
           ON 110 PERCENT DO SUSPEND_IMMEDIATE;

ALTER ACCOUNT SET RESOURCE_MONITOR = DATAPLAT_ACCOUNT;

-- ---------------------------------------------------------------------------------------
-- Terraform from a workstation: only the dev sandbox, through the dev developer AWS role.
-- ---------------------------------------------------------------------------------------
CREATE USER IF NOT EXISTS TERRAFORM_DEV
  TYPE = SERVICE
  DEFAULT_ROLE = PLATFORM_ADMIN
  WORKLOAD_IDENTITY = (
    TYPE = AWS
    ARN = 'arn:aws:iam::<AWS_ACCOUNT_ID>:role/dataplat-dev-developer'
  )
  COMMENT = 'Terraform run by a person against dev. Authenticates as the dev developer AWS role.';

GRANT ROLE PLATFORM_ADMIN TO USER TERRAFORM_DEV;

-- ---------------------------------------------------------------------------------------
-- Terraform from GitHub Actions: one user per GitHub environment. Each trusts exactly one
-- OIDC subject, so a job can only act as the environment it was approved for.
-- ---------------------------------------------------------------------------------------
CREATE USER IF NOT EXISTS TERRAFORM_GHA_DEV
  TYPE = SERVICE
  DEFAULT_ROLE = PLATFORM_ADMIN
  WORKLOAD_IDENTITY = (
    TYPE = OIDC
    ISSUER = 'https://token.actions.githubusercontent.com'
    SUBJECT = '<OIDC_SUBJECT_PREFIX>:environment:dev'
  )
  COMMENT = 'Terraform in GitHub Actions, environment dev.';

CREATE USER IF NOT EXISTS TERRAFORM_GHA_TST
  TYPE = SERVICE
  DEFAULT_ROLE = PLATFORM_ADMIN
  WORKLOAD_IDENTITY = (
    TYPE = OIDC
    ISSUER = 'https://token.actions.githubusercontent.com'
    SUBJECT = '<OIDC_SUBJECT_PREFIX>:environment:tst'
  )
  COMMENT = 'Terraform in GitHub Actions, environment tst.';

CREATE USER IF NOT EXISTS TERRAFORM_GHA_STG
  TYPE = SERVICE
  DEFAULT_ROLE = PLATFORM_ADMIN
  WORKLOAD_IDENTITY = (
    TYPE = OIDC
    ISSUER = 'https://token.actions.githubusercontent.com'
    SUBJECT = '<OIDC_SUBJECT_PREFIX>:environment:stg'
  )
  COMMENT = 'Terraform in GitHub Actions, environment stg.';

CREATE USER IF NOT EXISTS TERRAFORM_GHA_PRD
  TYPE = SERVICE
  DEFAULT_ROLE = PLATFORM_ADMIN
  WORKLOAD_IDENTITY = (
    TYPE = OIDC
    ISSUER = 'https://token.actions.githubusercontent.com'
    SUBJECT = '<OIDC_SUBJECT_PREFIX>:environment:prd'
  )
  COMMENT = 'Terraform in GitHub Actions, environment prd.';

GRANT ROLE PLATFORM_ADMIN TO USER TERRAFORM_GHA_DEV;
GRANT ROLE PLATFORM_ADMIN TO USER TERRAFORM_GHA_TST;
GRANT ROLE PLATFORM_ADMIN TO USER TERRAFORM_GHA_STG;
GRANT ROLE PLATFORM_ADMIN TO USER TERRAFORM_GHA_PRD;

-- ---------------------------------------------------------------------------------------
-- Check the result.
-- ---------------------------------------------------------------------------------------
SHOW USERS LIKE 'TERRAFORM_%';
