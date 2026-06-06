
create or replace table `/Ringier/Customer Lifetime Value/Query Generated/report total_tclv_login_state+loyalty`
USING parquet as

select
    t1.`month`,t1.publication,t1.login_state, t1.loyalty_segment, weighted_value*customers as tclv_value
from
(SELECT `month`,publication,login_state, loyalty_segment, sum(weighted_value) as weighted_value
FROM `/Ringier/Customer Lifetime Value/Query Generated/weighted_login_state+loyalty_report`
group by 1,2,3,4
) t1
left join
(
SELECT `month`,publication,login_state, loyalty_segment, sum(customers) as customers
FROM `/Ringier/Customer Lifetime Value/Query Generated/customers`
GROUP By 1,2,3,4
) t2
on
    t1.`month`=t2.`month`
AND t1.publication=t2.publication
AND t1.login_state=t2.login_state
AND t1.loyalty_segment=t2.loyalty_segment