




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
)

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
FROM `master`.`ri.foundry.main.dataset.af2861dd-7973-444f-b09a-9ba7f96fbc84`
) as loyalty
on
    main.`month`=loyalty.`month`
and main.publication=loyalty.publication
and main.user_status=loyalty.login_state_raw
