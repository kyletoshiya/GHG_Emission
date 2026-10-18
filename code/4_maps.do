
version 17
clear all
set more off


if "${path}" == "" {
    global path "`c(pwd)'"
    capture confirm file "${path}/data/NGMS_ENV_ready_2026_09_13.dta"
    if _rc {
        global path "`c(pwd)'/.."
    }
}
if "${data}" == "" global data "${path}/data"
if "${out}" == ""  global out  "${path}/output"


******************************************************************************
***Firm-level emissions (aggregated by region based on headquarters location)***
******************************************************************************


use "${out}/results/firm_year_totals.dta", clear


keep if year==2013|year==2023

merge m:1 firm_name using "${data}/firm_info.dta" , keepusing(firm_region) keep(master match) nogenerate
assert !missing(firm_region)


replace firm_region=firm_region/100000

* firm_region: region code used only for GIS mapping; differs from standard Korean administrative region codes
collapse (sum) emi_s1_firm emi_s2_firm, by(firm_region year)
sort year firm_region

replace emi_s1_firm = emi_s1_firm / 1e6
replace emi_s2_firm = emi_s2_firm / 1e6

preserve          
rename emi_s1_firm firm_s1_
rename emi_s2_firm firm_s2_
reshape wide firm_s1_ firm_s2_, i(firm_region) j(year) 

gen firm_s1_diff = firm_s1_2023 - firm_s1_2013
gen firm_s2_diff = firm_s2_2023 - firm_s2_2013

export delimited using "${out}/results/gis_firm.csv", replace
restore


***************************************************************************************
***Establishment-level emissions (aggregated by region based on establish location) ***
***************************************************************************************

use "${out}/results/KR_firm_estab_GHG_2012_2023.dta", clear

keep if year==2013|year==2023

preserve
use sigungu_code gis_code using "${data}/region_code.dta", clear
duplicates drop
tempfile rc
save `rc'
restore
merge m:1 sigungu_code using `rc', keep(master match) nogenerate
assert !missing(gis_code)


collapse (sum) emi_s1_estab emi_s2_estab (count) n_s1=emi_s1_estab n_s2=emi_s2_estab, by(gis_code year)
replace emi_s1_estab = . if n_s1 == 0
replace emi_s2_estab = . if n_s2 == 0
drop n_s1 n_s2


replace emi_s1_estab = emi_s1_estab / 1e6
replace emi_s2_estab = emi_s2_estab / 1e6

preserve          
rename emi_s1_estab est_s1_
rename emi_s2_estab est_s2_
reshape wide est_s1_ est_s2_, i(gis_code) j(year) 

gen est_s1_diff = est_s1_2023 - est_s1_2013
gen est_s2_diff = est_s2_2023 - est_s2_2013

export delimited using "${out}/results/gis_est.csv", replace
restore

