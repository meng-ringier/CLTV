create or replace table `/Ringier/Customer Lifetime Value/Query Generated/loyalty_ratio` USING parquet as
with
users_table as
(
    SELECT
        cast(`month` as string) as `month`,
        'blick.ch_de' as publication,
        user_status,
        loyalty_segment_1m as loyalty_segment,
        sum(device_count) as users,
        sum(pageview_count) as pageviews
    FROM `/Ringier/Blick Collaboration - Data Team/Data Team/BigQuery Exports/data connection/raw/dataform/rms-data-marts.df_blickde_reporting.user-metrics-monthly` -- rms-data-marts.df_blickde_reporting.user-metrics-monthly
    where user_status!='notSpecified'
    and `month`>='2025-08-01' and `month`<='2026-03-01'
    group by 1,2,3,4 order by 1,2,3,4
),

total_users_table as (
select
    `month`,
    user_status,
    publication,
    sum(users) as total_users,
    SUM(pageviews) as total_pageviews
from
    users_table
group by 1,2,3
),

loyalty_users as (
select
    `month`,
    publication,
    user_status,
    loyalty_segment,
    sum(users) as total_users,
    SUM(pageviews) as total_pageviews
from
    users_table
group by 1,2,3,4
)


   select
    main.`month`,
    main.user_status,
    main.loyalty_segment,
    main.publication,
    main.total_users/total_users_table.total_users as loyalty_ratio,
    main.total_pageviews/total_users_table.total_pageviews as loyalty_pageviews_ratio
from
   loyalty_users as main
left join
   total_users_table
on
    CAST(main.`month` AS STRING)=CAST(total_users_table.`month` AS STRING)
AND main.publication=total_users_table.publication
AND CAST(main.user_status AS STRING)=CAST(total_users_table.user_status as STRING)
where
    main.total_users is not null
order by 1,2,3,4