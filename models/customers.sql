

with
customers as
(
    SELECT `month`,'blick.ch_de' as publication, user_status, loyalty_segment_1m as loyalty_segment, sum(device_count) as users, sum(pageview_count) as pageviews
    FROM `/Ringier/Blick Collaboration - Data Team/Data Team/BigQuery Exports/data connection/raw/dataform/rms-data-marts.df_blickde_reporting.user-metrics-monthly` -- rms-data-marts.df_blickde_reporting.user-metrics-monthly
    where user_status!='notSpecified'
    group by 1,2,3,4 order by 1,2,3,4
),

rus as (
SELECT
    `month`,
    publication,
    rus_WEMF_and_foreign_traffic,
    monthly_subscribers,
    yearly_subscribers,
    consent_rate,
    no_consent_rate
FROM `/Ringier/Customer Lifetime Value/CLTV - Manual Monthly Data`
order by 1,2
),

consent_table as
(
SELECT
    `month`,
    publication,
    consent_rate,
    no_consent_rate
FROM `/Ringier/Customer Lifetime Value/CLTV - Manual Monthly Data`
order by 1,2
),

users as (
select
    `month`,
    publication,
    sum(users) as total_users
from
    customers
group by 1,2
),
rus_ratio_table as
(
select
    rus.`month`,
    rus.publication,
    rus.rus_WEMF_and_foreign_traffic/users.total_users as rus_ratio
from
    rus
left join
   users
on
    rus.`month`=users.`month`
AND rus.publication=users.publication
where
    total_users is not null
),

ground_truth_customer as (
--- Get ground truth customers with rus ratio
select
    main.`month`,
    main.publication,
    user_status,
    loyalty_segment,
    users*rus_ratio_table.rus_ratio as customers
from
   customers main
left join
   rus_ratio_table
on
    main.`month`=rus_ratio_table.`month`
AND main.publication=rus_ratio_table.publication
where rus_ratio is not null
order by 1,2,3,4
),

no_consent_customer as (

select
    main.`month`,
    main.publication,
    loyalty_segment,
    'No Consent' as login_state,
    sum(customers*consent_table.no_consent_rate) as customers
from
    ground_truth_customer main
left join
    consent_table
on
    main.`month`=consent_table.`month`
AND main.publication=consent_table.publication
group by 1,2,3,4
)


select
    *
from
    no_consent_customer
order by 1,2,3,4