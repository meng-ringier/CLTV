create or replace table `/Ringier/Customer Lifetime Value/Query Generated/weighted_device_login_state_report` USING parquet as

with
customer_table as (
SELECT `month`,publication, login_state, loyalty_segment, device, sum(customers) as customers
FROM `/Ringier/Customer Lifetime Value/Query Generated/customers_device_scope`
group by 1,2,3,4,5
order by 1
),
customer_login_state_table as (
SELECT `month`,publication, login_state,device, sum(customers) as customers
FROM `/Ringier/Customer Lifetime Value/Query Generated/customers_device_scope`
group by 1,2,3,4
order by 1
),


weight as
(

    SELECT
        main.`month`,
        main.publication,
        main.device,
        main.login_state,
        main.loyalty_segment,
        main.customers/customer_login_state_table.customers as weight
    FROM
        customer_table as main
    LEFT JOIN
        customer_login_state_table
    ON
        main.`month`=customer_login_state_table.`month`
    AND main.`publication`=customer_login_state_table.`publication`
    AND main.`login_state`=customer_login_state_table.`login_state`
    AND main.`device`=customer_login_state_table.`device`

)




select
     t1.`month`,
     t1.publication,
     t1.device,
     t1.login_state,
     type,
     SUM(weighted_value*weight) as weighted_value
from
    `/Ringier/Customer Lifetime Value/Query Generated/weighted_device_loyalty_login_state_report` t1
left join
    weight t2
on
            t1.`month`=t2.`month`
    and t1.publication=t2.publication
    and t1.login_state=t2.login_state
    and t1.loyalty_segment=t2.loyalty_segment
    and t1.device=t2.device

GROUP BY 1,2,3,4,5
order by 1,2,3,4,5