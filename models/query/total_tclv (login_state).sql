create or replace table `/Ringier/Customer Lifetime Value/Query Generated/report total_tclv_login_state`
USING parquet as
select
    CONCAT(YEAR(t1.`month`), '-Q', QUARTER(t1.`month`)) AS `quarter`,
    YEAR(t1.`month`)     AS `year`,
    t1.`month`,t1.publication,t1.login_state, weighted_value*customers as tclv_value
from
(SELECT `month`,publication,login_state, sum(weighted_value) as weighted_value
FROM `/Ringier/Customer Lifetime Value/Query Generated/weighted_login_state_report`
group by 1,2,3
) t1
left join
(
SELECT `month`,publication,login_state, sum(customers) as customers
FROM `/Ringier/Customer Lifetime Value/Query Generated/customers`
GROUP By 1,2,3
) t2
on
    t1.`month`=t2.`month`
AND t1.publication=t2.publication
AND t1.login_state=t2.login_state