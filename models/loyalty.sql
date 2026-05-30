

WITH
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
    SUM(newUsers) AS new_users

FROM `master`.`ri.foundry.main.dataset.11a884fb-8002-4862-8660-a2ae56b2f2ac` -- table: GA4_blick.ch_de_v2
GROUP BY 1,2,3
having login_state!='Other'
),

device_x_login_state as
(
    select *
    FROM(
    (
    SELECT
        main.`month`,
        main.publication,
        'No Consent' as login_state,
        users*(1-consent_rate) as users,
        new_users*(1-consent_rate) as new_users
    FROM
    (
    SELECT
        `month`,
        publication,
        sum(users) as users,
        sum(new_users) as new_users
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
        new_users
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
    new_users* loyalty_ratio as new_users
FROM
(
select
    *,
    case
        when login_state in ('Consent Only','No Consent') THEN 'notLoggedIn'
        when login_state in ('Logged-In') THEN 'notSubscribed'
        when login_state in ('Monthly Subscription','Yearly Subscription') THEN 'subscribed'
    end as user_status
from device_x_login_state
) as main
left join
(
SELECT *
FROM `master`.`ri.foundry.main.dataset.af2861dd-7973-444f-b09a-9ba7f96fbc84` -- table: CLTV V7 Loyalty Ratio (user_status+loyalty+device)
) as loyalty
on
    main.`month`=loyalty.`month`
and main.publication=loyalty.publication
and main.user_status=loyalty.login_state_raw
),

ga as
(
SELECT
    `month`,
    publication,
    loyalty_segment,
    sum(users) as users,
    sum(new_users) as new_users,
    sum(users)/sum(new_users) as lifetime
FROM ga_raw
group by 1,2,3
),

gam as (
SELECT
    CONCAT(substring(`date`, 1,7), '-01') as `month`,
    'blick.ch_de' as publication,
    SUM(impressions) as impressions
FROM `master`.`ri.foundry.main.dataset.395c5cd8-ea38-4165-83eb-eff53e6bb506`
group by 1,2
),

gotom as (
SELECT *
FROM `master`.`ri.foundry.main.dataset.1eb99170-02ac-4e43-9a10-d44989af5458` -- Gotom
),
rpm_table as
(
SELECT gotom.`month`, gotom.publication, gotom_revenue/impressions*1000 as rpm
FROM gotom
left join
gam
on
    gotom.`month`=gam.`month`
and gotom.publication=gam.publication
),
pageviews as
(
 SELECT
`month`,
'blick.ch_de' as publication,
loyalty_segment_1m as loyalty_segment,
sum(device_count) as users,
sum(pageview_count) as pageviews,
sum(pageview_count)/sum(device_count) as pageviews_per_user
FROM `master`.`ri.foundry.main.dataset.b2d1b95c-e3da-43d5-89cb-ed330e4a6b2a` -- rms-data-marts.df_blickde_reporting.user-metrics-monthly
group by 1,2,3
order by 1
),


impressions_per_view as (
SELECT
    gam.`month`,
    publication,
    impressions/page_views as impressions_per_pageviews
FROM gam
left join
(
select `month`, sum(pageviews) as page_views from pageviews
group by 1
) as pageviews
on
    gam.`month`=pageviews.`month`

),

unified as
(
select
    ga.`month`,
    ga.publication,
    ga.loyalty_segment,
    pageviews.pageviews_per_user as views_per_user,
    impressions_per_view.impressions_per_pageviews as impressions_per_pageviews,
    rpm_table.rpm as rpm,
    lifetime
from
    ga
left join
    pageviews
on
    ga.`month`=pageviews.`month`
and  ga.`publication`=pageviews.`publication`
and  ga.`loyalty_segment`=pageviews.`loyalty_segment`
left join
    impressions_per_view
on
    ga.`month`=impressions_per_view.`month`
and  ga.`publication`=impressions_per_view.`publication`
left join
    rpm_table
on
    ga.`month`=rpm_table.`month`
and  ga.`publication`=rpm_table.`publication`
order by 1,2,3
)

select
        views_per_user*impressions_per_pageviews*rpm/1000 as arpu,
        views_per_user*impressions_per_pageviews*rpm/1000*lifetime as advertising_value,
         `month`,
        publication,
        loyalty_segment,
        views_per_user,
        impressions_per_pageviews,
        views_per_user*impressions_per_pageviews as impressions_per_user,
        rpm,
        lifetime
from
unified