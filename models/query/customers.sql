create or replace table `/Ringier/Customer Lifetime Value/Query Generated/customers` USING parquet as
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

rus as (
SELECT
    cast(`month` as string) as `month`,
    publication,
    rus_WEMF_and_foreign_traffic,
    monthly_subscribers,
    yearly_subscribers,
    consent_rate,
    no_consent_rate
FROM `/Ringier/Customer Lifetime Value/CLTV - Manual Monthly Data`
order by 1,2
),

monthly_yearly_subscribers as (
SELECT
    cast(`month` as string) as `month`,
    publication,
    monthly_subscribers,
    yearly_subscribers,
    monthly_subscribers/(monthly_subscribers+yearly_subscribers) as monthly_subscribers_ratio,
    yearly_subscribers/(monthly_subscribers+yearly_subscribers) as yearly_subscribers_ratio
FROM `/Ringier/Customer Lifetime Value/CLTV - Manual Monthly Data`
order by 1,2
),

consent_table as
(
SELECT
    cast(`month` as string) as `month`,
    publication,
    consent_rate,
    no_consent_rate
FROM `/Ringier/Customer Lifetime Value/CLTV - Manual Monthly Data`
order by 1,2
),


loyalty_ratio_without_user_status as (
    select
    t1.`month`,
    t1.publication,
    t1.loyalty_segment,
    t1.total_users/t2.total_users as loyalty_ratio
     from
    (
    select
        `month`,
        publication,
        loyalty_segment,
        sum(users) as total_users
    from
        users_table
        GROUP BY 1,2,3
    ) as t1
    left join
    (
    select
        `month`,
        publication,
        sum(users) as total_users
    from
        users_table
        group by 1,2
    ) as t2
    on
        t1.`month`=t2.`month`
    AND         t1.`publication`=t2.`publication`

),

one_log_table as
(

  select
    t1.`month`,
    t1.publication,
    t1.loyalty_segment,
    onelog_customer*loyalty_ratio as onelog_customer
 from loyalty_ratio_without_user_status t1
 left join
(
SELECT
    cast(`month` as string) as `month`,
    publication,
    one_log_not_subscribed as onelog_customer
FROM `/Ringier/Customer Lifetime Value/CLTV - Manual Monthly Data`
order by 1,2
) t2
    on
        t1.`month`=t2.`month`
    AND  t1.`publication`=t2.`publication`


),

total_users_table as (
select
    `month`,
    user_status,
    publication,
    sum(users) as total_users
from
    users_table
group by 1,2,3
),

consent_users_table as (
select
    `month`,
    publication,
    loyalty_segment,
    sum(users) as users
from
    users_table
where
    user_status in ('subscribed', 'notSubscribed')
group by 1,2,3
order by 1,2,3
),

not_subscribed_users_table as (
select
    `month`,
    publication,
    loyalty_segment,
    sum(users) as users
from
    users_table
where
    user_status in ('notSubscribed')
group by 1,2,3
order by 1,2,3
),


subscribed_users_table as (
select
    `month`,
    publication,
    loyalty_segment,
    sum(users) as users
from
    users_table
where
    user_status in ('subscribed')
group by 1,2,3
order by 1,2,3
),

logged_in_ratio_table as
(
    select
        main.`month`,
        main.publication,
        main.loyalty_segment,
        main.users/consent_users_table.users as logged_in_ratio
    from
        not_subscribed_users_table as main
    left join
        consent_users_table
    on
        main.`month`=consent_users_table.`month`
    AND main.publication=consent_users_table.publication
    AND main.loyalty_segment=consent_users_table.loyalty_segment
    order by 1,2,3
),


subscribed_ratio_table as
(
    select
        main.`month`,
        main.publication,
        main.loyalty_segment,
        main.users/consent_users_table.users as subscribed_ratio
    from
        subscribed_users_table as main
    left join
        consent_users_table
    on
        main.`month`=consent_users_table.`month`
    AND main.publication=consent_users_table.publication
    AND main.loyalty_segment=consent_users_table.loyalty_segment
    order by 1,2,3
),

total_users_without_status_table as (
select
    `month`,
    publication,
    sum(users) as total_users
from
    users_table
group by 1,2
),

rus_ratio_table as
(
select
    rus.`month`,
    rus.publication,
    rus.rus_WEMF_and_foreign_traffic/total_users_without_status_table.total_users as rus_ratio
from
    rus
left join
   total_users_without_status_table
on
    rus.`month`=total_users_without_status_table.`month`
AND rus.publication=total_users_without_status_table.publication
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
   users_table main
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
    main.loyalty_segment,
    'No Consent' as login_state,
    sum(customers*consent_table.no_consent_rate) as customers
from
    ground_truth_customer main
left join
    consent_table
on
    main.`month`=consent_table.`month`
AND main.publication=consent_table.publication
left join
(
select *
from `/Ringier/Customer Lifetime Value/Query Generated/loyalty_ratio`
where user_status='notLoggedIn'
) as loyalty_ratio_table
on
    main.`month`=loyalty_ratio_table.`month`
AND main.publication=loyalty_ratio_table.publication
AND main.loyalty_segment=loyalty_ratio_table.loyalty_segment
group by 1,2,3,4
),

logged_in_customer as (
select
    main.`month`,
    main.publication,
    main.loyalty_segment,
    'Logged-In' as login_state,
    onelog_customer*loyalty_ratio*logged_in_ratio as customers
from
    logged_in_ratio_table as main
left join
(
select *
from `/Ringier/Customer Lifetime Value/Query Generated/loyalty_ratio`
where user_status='notSubscribed'
) as loyalty_ratio_table
on
    main.`month`=loyalty_ratio_table.`month`
AND main.publication=loyalty_ratio_table.publication
AND main.loyalty_segment=loyalty_ratio_table.loyalty_segment
left join
    one_log_table
on
    main.`month`=one_log_table.`month`
AND main.publication=one_log_table.publication
AND main.loyalty_segment=one_log_table.loyalty_segment
order by 1,2,3,4
),


monthly_subscription_customer as (
select
    main.`month`,
    main.publication,
    main.loyalty_segment,
    'Monthly Subscription' as login_state,

    onelog_customer*loyalty_ratio*subscribed_ratio*monthly_subscribers_ratio as customers
from
    subscribed_ratio_table as main
left join
(
select *
from `/Ringier/Customer Lifetime Value/Query Generated/loyalty_ratio`
where user_status='subscribed'
) as loyalty_ratio_table
on
    main.`month`=loyalty_ratio_table.`month`
AND main.publication=loyalty_ratio_table.publication
AND main.loyalty_segment=loyalty_ratio_table.loyalty_segment
left join
monthly_yearly_subscribers
on
    main.`month`=monthly_yearly_subscribers.`month`
AND main.publication=monthly_yearly_subscribers.publication
left join
    one_log_table
on
    main.`month`=one_log_table.`month`
AND main.publication=one_log_table.publication
AND main.loyalty_segment=one_log_table.loyalty_segment
order by 1,2,3,4
),



yearly_subscription_customer as (
select
    main.`month`,
    main.publication,
    main.loyalty_segment,
    'Yearly Subscription' as login_state,

    onelog_customer*loyalty_ratio*subscribed_ratio*yearly_subscribers_ratio as customers
from
    subscribed_ratio_table as main
left join
(
select *
from `/Ringier/Customer Lifetime Value/Query Generated/loyalty_ratio`
where user_status='subscribed'
) as loyalty_ratio_table
on
    main.`month`=loyalty_ratio_table.`month`
AND main.publication=loyalty_ratio_table.publication
AND main.loyalty_segment=loyalty_ratio_table.loyalty_segment
left join
monthly_yearly_subscribers
on
    main.`month`=monthly_yearly_subscribers.`month`
AND main.publication=monthly_yearly_subscribers.publication
left join
    one_log_table
on
    main.`month`=one_log_table.`month`
AND main.publication=one_log_table.publication
AND main.loyalty_segment=one_log_table.loyalty_segment
order by 1,2,3,4
),


unified as (
    select
        *
    from
        no_consent_customer
    union all
    select *
    from
        logged_in_customer
    union all
    select *
    from
        monthly_subscription_customer
    union all
    select *
    from
        yearly_subscription_customer
    order by 1,2,3,4
)


select
    *
from
    unified
union all
(
    select
        main.`month`,
        main.publication,
        main.loyalty_segment,
        'Consent Only' as login_state,
        main.customers - unified_customers.customers as customers
    from
    (
    select
        `month`,
        publication,
        loyalty_segment,
        SUM(customers) as customers
    from
        ground_truth_customer
    group by 1,2,3
    ) as main
    left join
    (
    select
        `month`,
        publication,
        loyalty_segment,
        SUM(customers) as customers
    from
        unified
    GROUP BY 1,2,3
    ) as unified_customers
    on
        main.`month`=unified_customers.`month`
    AND main.publication=unified_customers.publication
    AND main.loyalty_segment=unified_customers.loyalty_segment
)