-- Landing table for the order_items entity. Columns mirror tools/datagen/src/datagen/schemas.py.
-- Database and schema come from the session, so one file serves every environment.
create table if not exists order_items (
    order_item_id NUMBER(19,0),
    order_id NUMBER(19,0),
    product_id NUMBER(19,0),
    quantity NUMBER(10,0),
    unit_price NUMBER(12,2),
    _source_file varchar,
    _file_row_number number,
    _loaded_at timestamp_tz default current_timestamp()
);
