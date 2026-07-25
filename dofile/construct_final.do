

version 17
clear all
set more off

clear all

global data = "${main}/data"
global out = "${main}/out"


cap mkdir "${out}"
cap mkdir "${out}/results"

use "${data}/NGMS_ENV_matched.dta", clear
local N_input = _N
gen long input_row_id = _n
confirm variable sgg_code
label var sgg_code "Harmonized county code"
egen firm_id = group(firm_name), missing label
egen estab_id = group(firm_name est_name), missing label
egen firmyear_id = group(firm_id year), missing label
isid firm_id estab_id year

merge 1:1 firm_id estab_id year using ///
    "${out}/results/method_v3_scope1_completed_estab_emissions.dta", ///
    nogen keep(master match) keepusing( ///
    emi_s1_final emi_s1_is_est emi_s1_source)

merge 1:1 firm_id estab_id year using ///
    "${out}/results/method_v3_scope2_completed_estab_emissions.dta", ///
    nogen keep(master match) keepusing( ///
    emi_s2_final emi_s2_is_est emi_s2_source pred_s2_total_full)

label var input_row_id "Row number in NGMS_ENV_matched.dta"
label var emi_s1_final "Final scope 1 establishment emissions: actual if observed, else energy estimate"
label var emi_s2_final "Final scope 2 establishment emissions: actual if observed, else energy estimate"
label var emi_s1_is_est "1 if final scope 1 emission is estimated; 0 if actual"
label var emi_s2_is_est "1 if final scope 2 emission is estimated; 0 if actual"
label var emi_s1_source "Final scope 1 emission source"
label var emi_s2_source "Final scope 2 emission source"

order input_row_id firm_id firmyear_id estab_id year firm_name est_name address ///
    sgg_code sigungu ///
    est_emission_scope1 emi_s1_final emi_s1_is_est emi_s1_source ///
    est_emission_scope2 emi_s2_final emi_s2_is_est emi_s2_source ///
    pred_s2_total_full

assert _N == `N_input'
assert !missing(sgg_code)
foreach s in s1 s2 {
    assert inlist(emi_`s'_source, "actual", "estimated", "unfilled")
    assert emi_`s'_is_est == 0 if emi_`s'_source == "actual"
    assert emi_`s'_is_est == 1 if emi_`s'_source == "estimated"
    assert missing(emi_`s'_is_est) if emi_`s'_source == "unfilled"
    assert !missing(emi_`s'_final) if inlist(emi_`s'_source, "actual", "estimated")
    assert missing(emi_`s'_final) if emi_`s'_source == "unfilled"
}

notes: Final emissions are actual if observed, otherwise estimated; missing means unfilled.

capture drop _merge
drop input_row_id firm_id firmyear_id estab_id emi_s1_source emi_s2_source

drop est_emission_scope1 est_emission_scope2

ren emission_ngms emi_s1_firm
ren pred_s2_total_full emi_s2_firm
ren emi_s1_final emi_s1_estab
ren emi_s2_final emi_s2_estab
ren emi_s1_is_est emi_s1_src
ren emi_s2_is_est emi_s2_src

order year firm_name est_name address sido sido_code sigungu sgg_code gis_code ///
industry sub_industry product employee revenue energy water waste chemicals ///
emi_s1_firm emi_s1_estab emi_s1_src ///
emi_s2_firm emi_s2_estab emi_s2_src


lab var energy "estab energy (TJ)"
lab var water  "estab water (ton)"
lab var waste  "estab waste (ton)"
lab var chemicals "chemicals (ton)"
lab var product "estab major product"
lab var industry "estab 1-digit industry codes"
lab var sub_industry "estab 2-digit industry codes"

lab var sido_code "sido, numeric"
lab var sgg_code "county, harmonized, numeric"
lab var gis_code "county, harmonized, numeric (GIS)"

label define emission_src 0 "actual" 1 "estimated", replace
label values emi_s1_src emission_src
label values emi_s2_src emission_src

lab var emi_s1_firm "NGMS-reported firm-level Scope 1 total"
lab var emi_s1_estab "Final Scope 1 establishment-level emissions"
lab var emi_s1_src "0-actual; 1-estimated; missing-unfilled"
lab var emi_s2_firm "Predicted firm-level Scope 2 total"
lab var emi_s2_estab "Final Scope 2 establishment-level emissions"
lab var emi_s2_src "0-actual; 1-estimated; missing-unfilled"

drop gis_code
ren sgg_code sigungu_code
ren est_name estab_name

assert _N == `N_input'
assert !missing(sigungu_code)
assert missing(emi_s1_src) | inlist(emi_s1_src, 0, 1)
assert missing(emi_s2_src) | inlist(emi_s2_src, 0, 1)
assert missing(emi_s1_estab) == missing(emi_s1_src)
assert missing(emi_s2_estab) == missing(emi_s2_src)

compress
save "${out}/results/estab_emissions_final_v4.dta", replace
display as text "Wrote ${out}/results/estab_emissions_final_v4.dta"
