
create or replace table `/Ringier/Customer Lifetime Value/Query Generated/weighted_login_state+loyalty_report` USING parquet as

with

clean_ga4 as (
SELECT
    CAST(CONCAT(SUBSTRING(`yearMonth`,1,4), '-',SUBSTRING(`yearMonth`,5,6),'-','01') as date) as `month`,
    'blick.ch_de' as publication,
    CASE
        -- Consent Only
        WHEN
                LOWER(customUseruser_status) = '(not set)'
                OR LOWER(customUseruser_status) = 'notloggedin'
                OR LOWER(customUseruser_status) = 'notspecified'
            THEN 'Consent Only'
        -- Logged-In
        WHEN LOWER(customUseruser_status) = 'notsubscribed'

            THEN 'Logged-In'

        -- Monthly Subscription
        WHEN LOWER(customUseruser_status) = 'subscribed'
             AND (
                 LOWER(customUserproduct_name) LIKE '%monat%'
                 OR LOWER(customUserproduct_name) LIKE '%month%'
                 OR LOWER(customUserproduct_name) LIKE '%print%'
             )
            THEN 'Monthly Subscription'

        -- Yearly Subscription
        WHEN LOWER(customUseruser_status) = 'subscribed'
             AND (
                 LOWER(customUserproduct_name) LIKE '%jahr%'
                 OR LOWER(customUserproduct_name) LIKE '%yearly%'
             )
            THEN 'Yearly Subscription'

        ELSE 'Other'
    END AS login_state,

    SUM(totalUsers) AS users,
    SUM(newUsers) AS new_users,
    SUM(screenPageViews) as pageviews
FROM `master`.`ri.foundry.main.dataset.11a884fb-8002-4862-8660-a2ae56b2f2ac` -- table: GA4_blick.ch_de_v2
GROUP BY 1,2,3
having login_state!='Other'
),

login_state_table as
(
    select *
    FROM(
    (
    SELECT
        main.`month`,
        main.publication,
        'No Consent' as login_state,
        users*(1/consent_rate-1) as users,
        new_users*(1/consent_rate-1) as new_users,
        pageviews*(1/consent_rate-1) as pageviews
    FROM
    (
    SELECT
        `month`,
        publication,
        sum(users) as users,
        sum(new_users) as new_users,
        sum(pageviews) as pageviews

    FROM
        clean_ga4
    GROUP BY 1,2
    ) as main
    LEFT JOIN
    (
        SELECT
            `month`,
            publication,
            consent_rate
        FROM `master`.`ri.foundry.main.dataset.a7060680-7900-446b-b870-f990b63966d7`-- table: CLTV V7 Consent Rate
    ) consent
    on
     main.`month`= consent.`month`
    AND main.publication=consent.publication
    )
    union ALL
    (
    SELECT
        main.`month`,
        main.publication,
        login_state,
        users,
        new_users,
        pageviews
    from
        clean_ga4 as main
    )
)
),

ga_raw as (
SELECT
    main.`month`,
    main.publication,
    login_state,
    loyalty_segment,
    users*loyalty_ratio as users,
    new_users* loyalty_ratio as new_users,
    pageviews*loyalty_pageviews_ratio as pageviews,
    users/new_users as advertising_lifetime
FROM
(
select
    *,
    case
        when login_state in ('Consent Only','No Consent') THEN 'notLoggedIn'
        when login_state in ('Logged-In') THEN 'notSubscribed'
        when login_state in ('Monthly Subscription','Yearly Subscription') THEN 'subscribed'
    end as user_status
from login_state_table
) as main
left join
(
SELECT *
FROM
`/Ringier/Customer Lifetime Value/Query Generated/loyalty_ratio`
) as loyalty
on
    main.`month`=loyalty.`month`
and main.publication=loyalty.publication
and main.user_status=loyalty.user_status
),

customer_table as (
SELECT `month`,publication, login_state, loyalty_segment,sum(customers) as customers
FROM `/Ringier/Customer Lifetime Value/Query Generated/customers`
group by 1,2,3,4
order by 1
),


ga as
(
SELECT `month`, publication, login_state, loyalty_segment,
case when
    login_state='No Consent' then 'No Consent'
    else 'Consent' end as consent_status,

sum(users) as users,
sum(new_users) as new_users,
sum(pageviews) as pageviews,
sum(users)/sum(new_users) as lifetime
FROM ga_raw  -- GA Cleaned via Query
group by 1,2,3,4
),
rpm_table as
(
SELECT *
FROM `master`.`ri.foundry.main.dataset.85345020-40d0-4253-ba30-0a0c1d56098a` -- RPM
),

lifetime_table as
(
SELECT `month`, publication, login_state,loyalty_segment, sum(users)/sum(new_users) as lifetime
FROM `master`.`ri.foundry.main.dataset.5e7ef298-1664-4480-bbd5-ddf99073d0c6`   --GA Cleaned via Query
GROUP BY 1,2,3,4
),

impressions_per_view as (
SELECT *
FROM `master`.`ri.foundry.main.dataset.50303a1c-c1c7-480e-b2d5-8fe0cf8736b4` -- CLTV Impressions_per_views (login_state+consent_status)
),

unified as
(
select
    ga.`month`,
    ga.publication,
    ga.login_state,
    ga.loyalty_segment,
    pageviews,
    customer_table.customers,
    users,
    CASE
        WHEN ga.login_state in ('No Consent') and ga.loyalty_segment in ('Brand Lover','Loyal Reader','Returning Reader', 'Casual Reader') THEN pageviews/users
        WHEN ga.login_state in ('Consent Only') and ga.loyalty_segment in ('Brand Lover','Loyal Reader', 'Returning Reader') THEN pageviews/users
        WHEN ga.login_state in ('Logged-In') and ga.loyalty_segment in ('Brand Lover') THEN pageviews/users
        ELSE pageviews/customer_table.customers
    END as views_per_user,
    impressions_per_view.impressions_per_pageviews as impressions_per_pageviews,
    rpm_table.rpm as rpm,
    lifetime
from
    ga
left join
    impressions_per_view
on
    ga.`month`=impressions_per_view.`month`
and  ga.`publication`=impressions_per_view.`publication`
and  ga.`login_state`=impressions_per_view.`login_state`
left join
    rpm_table
on
    ga.`month`=rpm_table.`month`
and  ga.`publication`=rpm_table.`publication`
and  ga.`consent_status`=rpm_table.`consent_status`
left join
customer_table
on
     ga.`month`=customer_table.`month`
and  ga.`publication`=customer_table.`publication`
and  ga.`login_state`=customer_table.`login_state`
and  ga.`loyalty_segment`=customer_table.`loyalty_segment`

order by 1,2,3
),

advertising as (
select
        pageviews,
        customers,
        users,
        views_per_user,
        impressions_per_pageviews,
        views_per_user*impressions_per_pageviews as impressions_per_user,
        views_per_user*impressions_per_pageviews*rpm/1000*lifetime as advertising_value,
        views_per_user*impressions_per_pageviews*rpm/1000 as arpu,
        `month`,
        publication,
        login_state,
        loyalty_segment,
        rpm,
        lifetime
from
unified
),

subscription_arpu as
(
SELECT `month`,publication, login_state, loyalty_segment, avg(subscription_value) as arpu
FROM `master`.`ri.foundry.main.dataset.a53cdaec-91ea-4686-9f21-1ead7ba5ea9e` --- CLTV V7 Subscription ARPU (login_state+loyalty_segment+device)
group by 1,2,3,4
),
subscription_lifetime as
(
SELECT *, average_lifetime as lifetime
FROM `master`.`ri.foundry.main.dataset.36bd54ed-516e-4449-9341-6cc5b1b4cea2`-- CLTV V7 Subscription Liftetime(login_state+loyalty_segment)
),
subscription as
(
    select
     t1.`month`,
     t1.publication,
     t1.login_state,
     t1.loyalty_segment,
     'Subscription' as type,
     arpu,
     lifetime,
     CASE
        WHEN t1.login_state='Yearly Subscription' THEN arpu*lifetime/12
        ELSE arpu*lifetime END as weighted_value
    from
    subscription_lifetime t1
    left join
        subscription_arpu t2
    on
        t1.`month`=t2.`month`
    and t1.publication=t2.publication
    and t1.login_state=t2.login_state
    and t1.loyalty_segment=t2.loyalty_segment

)


select
     `month`,
     publication,
     login_state,
     loyalty_segment,
     'Advertising' as type,
     arpu,
     lifetime,
     advertising_value as weighted_value
from
    advertising
union all
(select *
 from subscription
)
