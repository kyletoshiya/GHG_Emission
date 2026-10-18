/*
2_estimate_missing.do
Expected-emissions residual allocation of the NGMS firm-year total to establishments, both scopes
jointly (see programs_estimate_missing.do). Also produces the energy-share comparison run (tier 2 for every
missing cell) under the tag estimates_energy. Run after 1a_firm_decomp_s1_s2.do.
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
cap mkdir "${out}"
cap mkdir "${out}/results"
cap mkdir "${out}/figures"
capture confirm file "${out}/results/firm_year_ngms_s1_s2.dta"
if _rc {
    display as error "Run 1a_firm_decomp_s1_s2.do first."
    exit 601
}
* parameters of the own-history tier (chosen with 3c_parameter_sensitivity.do): median of the 3 nearest own reporting
* years, bounded to [1/5, 5] x the firm fallback when the nearest report is more than 2 years away or fewer
* than 3 own years exist
if "${p_nn}"   == "" global p_nn   3
if "${p_lo}"   == "" global p_lo   0.2
if "${p_hi}"   == "" global p_hi   5
if "${p_bgap}" == "" global p_bgap 2
if "${p_bmin}" == "" global p_bmin 3
do "${path}/code/programs_estimate_missing.do"
allocate_joint, method(expected) nn(${p_nn}) lo(${p_lo}) hi(${p_hi}) bgap(${p_bgap}) bmin(${p_bmin}) tag(estimates)
allocate_joint, method(energy) tag(estimates_energy) novalidation
