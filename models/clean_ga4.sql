WITH
clean_ga4 as (
SELECT
    `month`,
    REGEXP_REPLACE(request_source, 'blick_', '') AS device,
    'blick.ch_de' as publication,
    CASE
        -- Consent Only
        WHEN
                LOWER(user_status) = '(not set)'
                OR LOWER(user_status) = 'notloggedin'
                OR LOWER(user_status) = 'notspecified'
            THEN 'Consent Only'
        -- Logged-In
        WHEN LOWER(user_status) = 'notsubscribed'

            THEN 'Logged-In'

        -- Monthly Subscription
        WHEN LOWER(user_status) = 'subscribed'
             AND (
                 LOWER(product_name) LIKE '%monat%'
                 OR LOWER(product_name) LIKE '%month%'
                 OR LOWER(product_name) LIKE '%print%'
             )
            THEN 'Monthly Subscription'

        -- Yearly Subscription
        WHEN LOWER(user_status) = 'subscribed'
             AND (
                 LOWER(product_name) LIKE '%jahr%'
                 OR LOWER(product_name) LIKE '%yearly%'
             )
            THEN 'Yearly Subscription'

        ELSE 'Other'
    END AS login_state,

    SUM(total_users) AS users,
    SUM(new_users) AS new_users

FROM `master`.`ri.foundry.main.dataset.c7e12b47-2d91-44ab-8158-428290301801` -- table: aggregatedWithMobileDesktop
GROUP BY 1,2,3,4
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
        main.device,
        'No Consent' as login_state,
        users*(1-consent_rate) as users,
        new_users*(1-consent_rate) as new_users
    FROM
    (
    SELECT
        `month`,
        publication,
        device,
        sum(users) as users,
        sum(new_users) as new_users
    FROM
        clean_ga4
    GROUP BY 1,2,3
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
        main.device,
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
    main.device,
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
FROM `master`.`ri.foundry.main.dataset.1b5af71c-dd37-45a0-b32b-3018361f6fdd` -- table: CLTV V7 Loyalty Ratio (user_status+loyalty+device)
) as loyalty
on
    main.`month`=loyalty.`month`
and main.publication=loyalty.publication
and main.device=loyalty.device
and main.user_status=loyalty.login_state_raw

