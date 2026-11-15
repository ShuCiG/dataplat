-- Landing table for the products entity. Columns mirror tools/datagen/src/datagen/schemas.py.
-- Database and schema come from the session, so one file serves every environment.
create table if not exists products (
    product_id NUMBER(19,0),
    name VARCHAR,
    category VARCHAR,
    price NUMBER(12,2),
    updated_at TIMESTAMP_TZ(6),
    _source_file varchar,
    _file_row_number number,
    _loaded_at timestamp_tz default current_timestamp()
);
