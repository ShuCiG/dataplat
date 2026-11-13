with days as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ var('calendar_start') ~ "' as date)",
        end_date="dateadd(year, 1, date_trunc('year', current_date))"
    ) }}

)

select
    to_number(to_char(date_day, 'YYYYMMDD')) as date_key,
    cast(date_day as date) as date_day,
    year(date_day) as year_number,
    quarter(date_day) as quarter_number,
    month(date_day) as month_number,
    monthname(date_day) as month_name,
    weekofyear(date_day) as week_of_year,
    dayofweekiso(date_day) as day_of_week,
    dayname(date_day) as day_name,
    dayofweekiso(date_day) in (6, 7) as is_weekend
from days
