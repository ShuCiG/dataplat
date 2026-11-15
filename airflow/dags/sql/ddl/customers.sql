-- Landing table for the customers entity. Columns mirror tools/datagen/src/datagen/schemas.py.
-- Database and schema come from the session, so one file serves every environment.
create table if not exists customers (
    customer_id NUMBER(19,0),
    email VARCHAR,
    first_name VARCHAR,
    last_name VARCHAR,
    country VARCHAR,
    created_at TIMESTAMP_TZ(6),
    updated_at TIMESTAMP_TZ(6),
    _source_file varchar,
    _file_row_number number,
    _loaded_at timestamp_tz default current_timestamp()
);
