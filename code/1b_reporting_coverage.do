/*
1b_reporting_coverage.do

Descriptive diagnostics of the analysis input, computed inside the replication
package from the ready file and the 1a decomposition:
  (i)   sample coverage of the national GHG inventory, by year
        - coverage_ngms   : sum of NGMS firm totals (S1+S2) / national total
        - coverage_s1     : sum of decomposed NGMS_S1 / national total  (preferred:
                            both numerator and denominator are direct emissions)
        Scope 2 is never compared with the national inventory because purchased
        electricity is already counted as scope 1 of power producers in the sample.
  (ii)  ENV-Info vs NGMS consistency among complete-reporting firm-years, by year
  (iii) establishment-year reporting counts by scope (basis for the manuscript's Table 1)

Input : data/NGMS_ENV_ready_2026_09_13.dta
        output/results/firm_year_ngms_s1_s2.dta      (from 1a)
Output: output/results/coverage_by_year.dta
        output/results/env_ngms_consistency_by_year.dta
        output/results/reporting_counts.dta
*/

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
local ready "NGMS_ENV_ready_2026_09_13"

capture confirm file "${out}/results/firm_year_ngms_s1_s2.dta"
if _rc {
    display as error "Run 1a_firm_decomp_s1_s2.do first."
    exit 601
}

* ---------------------------------------------------------------------------
* (i) Coverage of the national inventory
* ---------------------------------------------------------------------------
use "${out}/results/firm_year_ngms_s1_s2.dta", clear
collapse (sum) ngms = emission_ngms ngms_s1 = NGMS_S1 ngms_s2 = NGMS_S2, by(year)

* National total GHG emissions, million tCO2eq.
* TODO: record the inventory edition, GWP basis and LULUCF treatment before citing.
gen double national = .
replace national = 719.08 if year == 2012
replace national = 727.48 if year == 2013
replace national = 722.65 if year == 2014
replace national = 725.05 if year == 2015
replace national = 735.56 if year == 2016
replace national = 756.27 if year == 2017
replace national = 780.14 if year == 2018
replace national = 757.15 if year == 2019
replace national = 709.47 if year == 2020
replace national = 739.51 if year == 2021
replace national = 722.03 if year == 2022
replace national = 707.20 if year == 2023
replace national = national * 1e6
assert !missing(national)

gen double coverage_ngms = ngms    / national
gen double coverage_s1   = ngms_s1 / national
label var ngms          "Sample NGMS totals (S1+S2), tCO2eq"
label var ngms_s1       "Sample decomposed NGMS scope 1, tCO2eq"
label var ngms_s2       "Sample decomposed NGMS scope 2, tCO2eq"
label var national      "National total GHG emissions, tCO2eq"
label var coverage_ngms "Sample NGMS (S1+S2) / national total"
label var coverage_s1   "Sample NGMS scope 1 / national total"
save "${out}/results/coverage_by_year.dta", replace
list year coverage_ngms coverage_s1, noobs

* ---------------------------------------------------------------------------
* (ii) ENV vs NGMS consistency (complete-reporting firm-years)
* ---------------------------------------------------------------------------
use "${out}/results/firm_year_ngms_s1_s2.dta", clear
gen double ratio_c = env_ratio if complete
gen byte within1 = abs(ratio_c - 1) <= 0.01 if complete
gen byte off10   = abs(ratio_c - 1) >  0.10 if complete
gen one = 1
collapse (count) firm_years = one (sum) complete_fy = complete within1_fy = within1 off10_fy = off10 ///
         (median) median_ratio = ratio_c, by(year)
label var firm_years   "Firm-years in sample"
label var complete_fy  "Firm-years with all establishments reporting both scopes"
label var within1_fy   "Complete firm-years with ENV (S1+S2) within 1% of NGMS"
label var off10_fy     "Complete firm-years off NGMS by more than 10%"
label var median_ratio "Median ENV (S1+S2) / NGMS among complete firm-years"
save "${out}/results/env_ngms_consistency_by_year.dta", replace
list, noobs abbreviate(14)

* ---------------------------------------------------------------------------
* (iii) Establishment-year reporting counts by scope
* ---------------------------------------------------------------------------
use "${data}/`ready'.dta", clear
gen byte rep_s1 = !missing(est_emission_scope1)
gen byte rep_s2 = !missing(est_emission_scope2)
gen one = 1
collapse (count) estab_years = one (sum) reported_s1 = rep_s1 reported_s2 = rep_s2
gen missing_s1 = estab_years - reported_s1
gen missing_s2 = estab_years - reported_s2
gen double share_reported_s1 = reported_s1 / estab_years
gen double share_reported_s2 = reported_s2 / estab_years
save "${out}/results/reporting_counts.dta", replace
list, noobs
display as text "1b complete."
