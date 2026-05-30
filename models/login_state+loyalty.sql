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
    new_users* loyalty_ratio as new_users,
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
SELECT `month`, publication, login_state, loyalty_segment,
case when
    login_state='No Consent' then 'No Consent'
    else 'Consent' end as consent_status,

sum(users) as users, sum(new_users) as new_users, sum(users)/sum(new_users) as lifetime
FROM ga_raw  -- GA Cleaned via Query
group by 1,2,3,4
),
rpm_table as
(
SELECT *
FROM `master`.`ri.foundry.main.dataset.85345020-40d0-4253-ba30-0a0c1d56098a` -- RPM
),
pageviews as
(
SELECT `month`, publication, login_state,loyalty_segment, sum(page_views) as page_views
FROM `master`.`ri.foundry.main.dataset.32900f04-0b28-4fee-a8b6-cfa069a4480c` -- CLTV V7 Manual GA4 (login_state+loyalty)
GROUP BY 1,2,3,4
),

impressions_per_view as (
SELECT *
FROM `master`.`ri.foundry.main.dataset.50303a1c-c1c7-480e-b2d5-8fe0cf8736b4` -- CLTV Impressions_per_views (login_state+consent_status)
),

unified as
(
select
    ga.`month`, ga.publication, ga.login_state,
    page_views/users as views_per_user,
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
and  ga.`login_state`=pageviews.`login_state`
and  ga.`loyalty_segment`=pageviews.`loyalty_segment`
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
order by 1,2,3
)

select
        views_per_user*impressions_per_pageviews*rpm/1000*lifetime as advertising_value,
        CONCAT(`month`,'-01') as `month`,
        publication,
        login_state,
        loyalty_segment,
        views_per_user,
        impressions_per_pageviews,
        views_per_user*impressions_per_pageviews as impressions_per_user,
        rpm,
        lifetime
from
unified