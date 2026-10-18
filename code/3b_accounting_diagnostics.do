/*
3b_accounting_diagnostics.do -- accounting diagnostics of the released data (run after 2 and 4).

(i)   Conservation by year and by cause: final scope 1 + scope 2 of a firm-year versus its NGMS total.
        exact          : |gap| <= 1e-6 x NGMS
        unfilled       : at least one cell left unfilled (no energy / inconsistent reports)
        inconsistent   : reported subtotals exceed NGMS by more than 2% (flagged in 1a)
        complete_short : every cell reported but ENV total < NGMS (nothing to allocate to)
        reported_over  : reported subtotals exceed NGMS within the 2% tolerance (reported values kept; missing cells set to zero)
(ii)  Final status of establishment-scope cells by source, with emission shares.
(iii) Distribution of the firm-year ratio R / expected emissions and the flag.
(iv)  Years to the nearest own report for cells estimated from own history.
(v)   Comparison with the energy-share key (estimates_energy): share of estimated emissions re-assigned
      across establishments and across county-years.

Inputs : output/results/estimates_completed_estab_emissions.dta, estimates_firm_year.dta, estimates_energy_completed_estab_emissions.dta
Outputs: output/results/conservation_by_year.dta, conservation_by_cause.dta, final_status_by_scope.dta,
         ratio_distribution.dta, gap_distribution.dta, method_comparison.dta
*/
version 17
clear all
set more off
if "${path}" == "" {
    global path "`c(pwd)'"
    capture confirm file "${path}/output/results/estimates_completed_estab_emissions.dta"
    if _rc {
        global path "`c(pwd)'/.."
    }
}
if "${out}" == "" global out "${path}/output"
local R "${out}/results"

* ---------------------------------------------------------------- (i) conservation
use "`R'/estimates_firm_year.dta", clear
gen double D = emission_ngms - s1_final_fy - s2_final_fy
gen double Drel = D / emission_ngms
gen str16 cause = ""
replace cause = "exact"          if abs(D) <= 1e-6 * emission_ngms
replace cause = "unfilled"       if cause == "" & n_unfilled > 0
replace cause = "inconsistent"   if cause == "" & phi_conflict == 1
replace cause = "complete_short" if cause == "" & n_miss_cells == 0 & D > 0
replace cause = "reported_over"  if cause == "" & D < 0
replace cause = "other"          if cause == ""
label var D "Unallocated residual: NGMS total minus final S1 + S2"
gen one = 1
quietly count
local nfy = r(N)
gen double D_posv = max(D, 0)
gen double D_negv = max(-D, 0)
preserve
    collapse (count) firm_years = one (sum) D_sum = D D_pos = D_posv D_neg = D_negv ngms = emission_ngms, by(cause)
    egen double ngms_all = total(ngms)
    gen double share_fy = firm_years / `nfy'
    gen double D_share_of_total_ngms = D_sum / ngms_all
    gen double D_pos_share = D_pos / ngms_all
    gen double D_neg_share = D_neg / ngms_all
    label var D_pos_share "Gross unallocated: sum of max(NGMS - final, 0) / total NGMS"
    label var D_neg_share "Gross over-recorded: sum of max(final - NGMS, 0) / total NGMS"
    drop ngms_all
    save "`R'/conservation_by_cause.dta", replace
    list, noobs
restore
preserve
    gen byte exact = cause == "exact"
    gen byte within2 = abs(Drel) <= 0.02
    gen double ngms_exact = emission_ngms * exact
    gen double D_pos = max(D, 0)
    collapse (count) firm_years = one (sum) exact_fy = exact within2_fy = within2 ngms = emission_ngms ngms_exact D_unallocated = D_pos, by(year)
    gen double share_exact_fy   = exact_fy / firm_years
    gen double share_exact_ngms = ngms_exact / ngms
    gen double share_within2_fy = within2_fy / firm_years
    gen double unallocated_share = D_unallocated / ngms
    save "`R'/conservation_by_year.dta", replace
    list year firm_years exact_fy share_exact_fy share_exact_ngms share_within2_fy unallocated_share, noobs
restore

* ---------------------------------------------------------------- (ii) final status by scope and source
use "`R'/estimates_completed_estab_emissions.dta", clear
tempfile st
clear
set obs 0
gen byte scope = .
gen str14 status = ""
gen estab_years = .
gen double emissions = .
save `st', replace
foreach g in 1 2 {
    use "`R'/estimates_completed_estab_emissions.dta", clear
    gen one = 1
    collapse (count) estab_years = one (sum) emissions = s`g'_emi_final, by(s`g'_src)
    rename s`g'_src status
    gen byte scope = `g'
    append using `st'
    save `st', replace
}
use `st', clear
bys scope: egen double tot_n = total(estab_years)
bys scope: egen double tot_e = total(emissions)
gen double share_estab_years = estab_years / tot_n
gen double share_emissions   = emissions / tot_e
drop tot_n tot_e
gen byte ord = cond(status == "reported", 1, cond(status == "own_history", 2, cond(status == "firm_fallback", 3, cond(status == "zero_residual", 4, 5))))
sort scope ord
drop ord
save "`R'/final_status_by_scope.dta", replace
list, noobs

* ---------------------------------------------------------------- (iii) ratio distribution
use "`R'/estimates_firm_year.dta", clear
keep if n_miss_cells > 0
gen byte has_ratio = ratio != .
quietly count
local n_miss = r(N)
quietly summarize R, meanonly
local Rtot = r(sum)
foreach q in 5 10 25 50 75 90 95 {
    _pctile ratio if has_ratio, p(`q')
    local p`q' = r(r1)
}
quietly count if ratio_flag == 1
local nflag = r(N)
quietly summarize R if ratio_flag == 1, meanonly
local Rflag = r(sum)
quietly count if R == 0
local nR0 = r(N)
quietly count if ratio >= 0.5 & ratio <= 2
local n_half2 = r(N)
quietly summarize R if ratio >= 0.5 & ratio <= 2, meanonly
local R_half2 = r(sum)
clear
set obs 1
gen firm_years_with_missing = `n_miss'
gen firm_years_R_zero = `nR0'
foreach q in 5 10 25 50 75 90 95 {
    gen double ratio_p`q' = `p`q''
}
gen flagged_fy = `nflag'
gen double flagged_share_fy = `nflag' / `n_miss'
gen double flagged_share_residual = `Rflag' / `Rtot'
gen within_hd_fy = `n_half2'
gen double within_hd_share_residual = `R_half2' / `Rtot'
save "`R'/ratio_distribution.dta", replace
list, noobs

* ---------------------------------------------------------------- (iv) gap distribution of own-history cells
use "`R'/estimates_completed_estab_emissions.dta", clear
tempfile gp
clear
set obs 0
gen byte scope = .
gen str8 gap_class = ""
gen cells = .
gen double emissions = .
save `gp', replace
foreach g in 1 2 {
    use "`R'/estimates_completed_estab_emissions.dta", clear
    keep if s`g'_miss
    gen str8 gap_class = cond(s`g'_own_gap == ., "none", cond(s`g'_own_gap <= 1, "1", cond(s`g'_own_gap <= 3, "2-3", cond(s`g'_own_gap <= 6, "4-6", "7+"))))
    gen one = 1
    collapse (count) cells = one (sum) emissions = s`g'_emi_final, by(gap_class)
    gen byte scope = `g'
    append using `gp'
    save `gp', replace
}
use `gp', clear
bys scope: egen double tot_n = total(cells)
bys scope: egen double tot_e = total(emissions)
gen double share_cells = cells / tot_n
gen double share_emissions = emissions / tot_e
drop tot_n tot_e
sort scope gap_class
save "`R'/gap_distribution.dta", replace
list, noobs

* ---------------------------------------------------------------- (v) comparison with the energy-share key
use "`R'/estimates_completed_estab_emissions.dta", clear
keep firm_id estab_id year sigungu_code s1_emi_final s2_emi_final s1_miss s2_miss
rename s1_emi_final f1_exp
rename s2_emi_final f2_exp
merge 1:1 firm_id estab_id year using "`R'/estimates_energy_completed_estab_emissions.dta", assert(match) nogenerate keepusing(s1_emi_final s2_emi_final)
rename s1_emi_final f1_en
rename s2_emi_final f2_en
tempfile cmp
clear
set obs 0
gen byte scope = .
gen double estimated_total = .
gen double reassigned_estab_share = .
gen double reassigned_county_year_share = .
save `cmp', replace
foreach g in 1 2 {
    use "`R'/estimates_completed_estab_emissions.dta", clear
    keep firm_id estab_id year sigungu_code s`g'_emi_final s`g'_miss
    rename s`g'_emi_final fexp
    merge 1:1 firm_id estab_id year using "`R'/estimates_energy_completed_estab_emissions.dta", assert(match) nogenerate keepusing(s`g'_emi_final)
    rename s`g'_emi_final fen
    quietly summarize fexp if s`g'_miss, meanonly
    local est_tot = r(sum)
    gen double dif = abs(fexp - fen) if s`g'_miss
    quietly summarize dif, meanonly
    local re_estab = r(sum) / 2 / `est_tot'
    collapse (sum) fexp fen, by(year sigungu_code)
    gen double d = abs(fexp - fen)
    quietly summarize d, meanonly
    local re_cty = r(sum) / 2 / `est_tot'
    clear
    set obs 1
    gen byte scope = `g'
    gen double estimated_total = `est_tot'
    gen double reassigned_estab_share = `re_estab'
    gen double reassigned_county_year_share = `re_cty'
    append using `cmp'
    save `cmp', replace
}
use `cmp', clear
label var reassigned_estab_share "Share of estimated emissions assigned to a different establishment than under the energy-share key"
label var reassigned_county_year_share "Share of estimated emissions assigned to a different county-year than under the energy-share key"
sort scope
save "`R'/method_comparison.dta", replace
list, noobs
display as text "3b_accounting_diagnostics complete."
