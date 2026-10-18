/*
3a_build_final_dataset.do -- assemble the final establishment-year dataset .

Run after 1a and 2. Inputs: data/NGMS_ENV_ready_2026_09_13.dta, output/results/firm_year_ngms_s1_s2.dta,
output/results/estimates_completed_estab_emissions.dta.
Outputs: output/results/firm_year_totals.dta           (firm-year NGMS total and final scope totals)
         output/results/KR_firm_estab_GHG_2012_2023.dta             (released dataset: identifiers, attributes,
                                                                   NGMS total, firm-year scope totals, establishment
                                                                   emissions with source indicators)
         output/results/KR_firm_estab_GHG_2012_2023_diagnostics.dta (companion file, same keys: reported subtotals,
                                                                   residual, expected emissions, ratio and flag,
                                                                   fallback share and source, reporting gaps)
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

use "${data}/NGMS_ENV_ready_2026_09_13.dta", clear
local N_input = _N
egen firm_id     = group(firm_name), missing label
egen estab_id    = group(firm_name est_name), missing label
isid firm_id estab_id year
label values firm_id .
label values estab_id .
merge 1:1 firm_id estab_id year using "${out}/results/estimates_completed_estab_emissions.dta", assert(match) nogenerate ///
    keepusing(emission_ngms phi phi_source phi_conflict R W ratio ratio_flag n_unfilled fy_cons fy_target ///
              s1_Y s2_Y s1_final_fy s2_final_fy ///
              s1_emi_final s1_src s1_expct s1_own_gap s1_own_n s1_own_clipped s1_unfill s1_is_est ///
              s2_emi_final s2_src s2_expct s2_own_gap s2_own_n s2_own_clipped s2_unfill s2_is_est)
assert _N == `N_input'
foreach g in 1 2 {
    assert inlist(s`g'_src, "reported", "own_history", "firm_fallback", "zero_residual", "unfilled")
    assert !missing(s`g'_emi_final) if s`g'_src != "unfilled"
    assert missing(s`g'_emi_final) if s`g'_src == "unfilled"
    assert s`g'_emi_final == est_emission_scope`g' if s`g'_src == "reported"
}
* conservation: final S1 + S2 = max(NGMS, reported subtotals) whenever fy_cons == 1
assert abs(s1_final_fy + s2_final_fy - fy_target) <= 1e-6 * fy_target if fy_cons == 1

foreach g in 1 2 {
    gen byte emi_s`g'_src = .
    replace emi_s`g'_src = 0 if s`g'_src == "reported"
    replace emi_s`g'_src = 1 if s`g'_src == "own_history"
    replace emi_s`g'_src = 2 if s`g'_src == "firm_fallback"
    replace emi_s`g'_src = 3 if s`g'_src == "zero_residual"
    drop s`g'_src s`g'_is_est
}
drop est_emission_scope1 est_emission_scope2 gis_code id name_revised
label var firm_id  "Firm identifier (integer, constant over years)"
label var estab_id "Establishment identifier (integer, constant over years; nested in firm_id)"
rename emission_ngms emi_total_firm
rename s1_final_fy  emi_s1_firm
rename s2_final_fy  emi_s2_firm
rename s1_Y         emi_s1_firm_reported
rename s2_Y         emi_s2_firm_reported
rename R            emi_firm_residual
rename W            emi_firm_expected
rename ratio        emi_firm_ratio
rename ratio_flag   emi_firm_ratio_flag
rename phi_conflict emi_firm_inconsistent
rename fy_cons      emi_firm_reconciled
gen double emi_firm_ngms_gap = emi_total_firm - emi_s1_firm - emi_s2_firm
rename n_unfilled   emi_firm_n_unfilled
rename phi          emi_s1_share_fallback
rename phi_source   emi_fallback_src
rename s1_emi_final emi_s1_estab
rename s2_emi_final emi_s2_estab
rename s1_expct     emi_s1_expected
rename s2_expct     emi_s2_expected
rename s1_own_gap   emi_s1_gap
rename s2_own_gap   emi_s2_gap
rename s1_own_n     emi_s1_nyears
rename s2_own_n     emi_s2_nyears
rename s1_own_clipped emi_s1_bounded
rename s2_own_clipped emi_s2_bounded
rename s1_unfill    emi_s1_unfilled_reason
rename s2_unfill    emi_s2_unfilled_reason
rename est_name     estab_name
rename ksic_sec     firm_industry
tostring ksic2, generate(firm_sub_industry) format(%02.0f)
replace firm_sub_industry = "" if missing(ksic2)
drop ksic2
drop fy_target

label define emission_src 0 "reported in ENV-Info" 1 "estimated from own reports in other years" ///
    2 "estimated from the firm's other establishments" 3 "zero (reported emissions already reach the NGMS total)", replace
label values emi_s1_src emission_src
label values emi_s2_src emission_src
label var emi_total_firm        "NGMS-reported firm-year total (scope 1 + scope 2), tCO2eq"
label var emi_s1_firm           "Firm-year scope 1 total: sum of final establishment values"
label var emi_s2_firm           "Firm-year scope 2 total: sum of final establishment values"
label var emi_s1_firm_reported  "Firm-year scope 1 subtotal reported in ENV-Info"
label var emi_s2_firm_reported  "Firm-year scope 2 subtotal reported in ENV-Info"
label var emi_firm_residual     "Unreported residual: max(NGMS total - reported subtotals, 0)"
label var emi_firm_expected     "Sum of expected emissions of the firm-year's estimable missing cells"
label var emi_firm_ratio        "Residual / expected emissions (consistency of NGMS with ENV-Info-based expectations)"
label var emi_firm_ratio_flag   "1 if emi_firm_ratio lies outside [1/3, 3]"
label var emi_firm_inconsistent "1 if reported ENV-Info subtotals exceed the NGMS total by more than 2%"
label var emi_firm_reconciled   "1 if final scope 1 + scope 2 equal max(NGMS total, reported subtotals) (within 1e-6)"
label var emi_firm_ngms_gap     "NGMS total minus final scope 1 + scope 2 (tCO2eq; positive = unallocated)"
label var emi_firm_n_unfilled   "Number of unfilled establishment-scope cells in the firm-year"
label var emi_s1_share_fallback "Firm-year scope 1 share used in the firm fallback (1a, 4-step rule)"
label var emi_fallback_src      "Source of the fallback share: 1 observed, 2 own-firm interpolation, 3 partial, 4 cell"
label var emi_s1_estab          "Final scope 1 establishment emissions, tCO2eq"
label var emi_s2_estab          "Final scope 2 establishment emissions, tCO2eq"
label var emi_s1_src            "0 reported; 1 own other-year reports; 2 firm's other estabs; 3 zero; . unfilled"
label var emi_s2_src            "0 reported; 1 own other-year reports; 2 firm's other estabs; 3 zero; . unfilled"
label var emi_s1_expected       "Expected scope 1 emissions of a missing cell before reconciliation (intensity x energy)"
label var emi_s2_expected       "Expected scope 2 emissions of a missing cell before reconciliation (intensity x energy)"
label var emi_s1_gap            "Years to the nearest own scope 1 report used (missing cells with own history)"
label var emi_s2_gap            "Years to the nearest own scope 2 report used (missing cells with own history)"
label var emi_s1_nyears         "Number of own reporting years used for the scope 1 intensity"
label var emi_s2_nyears         "Number of own reporting years used for the scope 2 intensity"
label var emi_s1_bounded        "1 if the own-history scope 1 intensity was bounded to the firm fallback"
label var emi_s2_bounded        "1 if the own-history scope 2 intensity was bounded to the firm fallback"
label var emi_s1_unfilled_reason "Reason a missing scope 1 cell is unfilled: no_energy or inconsistent"
label var emi_s2_unfilled_reason "Reason a missing scope 2 cell is unfilled: no_energy or inconsistent"
label var sigungu_code          "County code, harmonized to 2015 divisions (KOSIS)"
label var firm_industry         "Firm 1-digit industry code"
label var firm_sub_industry     "Firm 2-digit industry code"
label var energy    "Establishment energy use (TJ)"
label var water     "Establishment water use (ton)"
label var waste     "Establishment waste generation (ton)"
label var chemicals "Establishment chemical emissions (ton)"
label var product   "Establishment main product"
label var industry  "Establishment 1-digit industry code"
label var sub_industry "Establishment 2-digit industry code"

assert _N == `N_input'
assert !missing(sigungu_code)
compress
* companion diagnostics file (technical variables, same keys as the released dataset)
preserve
    keep year firm_id firm_name estab_id estab_name emi_total_firm emi_s1_firm emi_s2_firm emi_s1_firm_reported emi_s2_firm_reported ///
         emi_firm_residual emi_firm_expected emi_firm_ratio emi_firm_ratio_flag emi_firm_inconsistent emi_firm_reconciled emi_firm_ngms_gap emi_firm_n_unfilled ///
         emi_s1_share_fallback emi_fallback_src ///
         emi_s1_estab emi_s1_src emi_s1_expected emi_s1_gap emi_s1_nyears emi_s1_bounded emi_s1_unfilled_reason ///
         emi_s2_estab emi_s2_src emi_s2_expected emi_s2_gap emi_s2_nyears emi_s2_bounded emi_s2_unfilled_reason
    order year firm_id firm_name estab_id estab_name
    save "${out}/results/KR_firm_estab_GHG_2012_2023_diagnostics.dta", replace
restore
* firm-year totals (for maps that assign the same final scope totals to headquarters and to establishments)
preserve
    keep year firm_id firm_name emi_total_firm emi_s1_firm emi_s2_firm emi_firm_reconciled emi_firm_ngms_gap
    bys firm_id year: keep if _n == 1
    label var emi_s1_firm "Firm-year scope 1 total: sum of final establishment values"
    label var emi_s2_firm "Firm-year scope 2 total: sum of final establishment values"
    sort firm_id year
    save "${out}/results/firm_year_totals.dta", replace
restore
* released dataset: drop the technical variables
drop emi_s1_firm_reported emi_s2_firm_reported emi_firm_residual emi_firm_expected emi_firm_ratio emi_firm_ratio_flag ///
     emi_firm_inconsistent emi_firm_reconciled emi_firm_ngms_gap emi_firm_n_unfilled emi_s1_share_fallback emi_fallback_src ///
     emi_s1_expected emi_s1_gap emi_s1_nyears emi_s1_bounded emi_s1_unfilled_reason ///
     emi_s2_expected emi_s2_gap emi_s2_nyears emi_s2_bounded emi_s2_unfilled_reason
order year firm_id firm_name estab_id estab_name address sido sido_code sigungu sigungu_code ///
      industry sub_industry firm_industry firm_sub_industry product employee revenue energy water waste chemicals ///
      emi_total_firm emi_s1_firm emi_s2_firm emi_s1_estab emi_s1_src emi_s2_estab emi_s2_src
save "${out}/results/KR_firm_estab_GHG_2012_2023.dta", replace
display as text "Wrote ${out}/results/KR_firm_estab_GHG_2012_2023.dta, KR_firm_estab_GHG_2012_2023_diagnostics.dta and firm_year_totals.dta"
