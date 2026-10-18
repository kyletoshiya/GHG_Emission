/*
3c_parameter_sensitivity.do -- sensitivity of the own-history tier to its parameters (run after 2).

Leave-one-year-out test on reported establishment-scope cells with energy > 0: the cell's scope intensity is
predicted from the establishment's other reporting years that are at least k years away (k = 1 ... 8), with
the median over the nn nearest such years, optionally bounded to [1/b, b] x the firm-level fallback intensity
(the scope intensity of the firm's other establishments reporting both scopes, computed without the cell). The
prediction (intensity x energy) is compared with
the reported value. Errors: median absolute percentage error and mean absolute error divided by the firm-year
total (scope 1 + scope 2) of reported emissions. The firm-level fallback alone is the reference.
Variants: nn in {1, 3, 5}; bound b in {none, 2, 3, 5, 10}; conditional bounds (applied only when the nearest
own report is more than 2 years away or fewer than 3 own years exist).

Inputs : data/NGMS_ENV_ready_2026_09_13.dta, output/results/firm_year_ngms_s1_s2.dta
Output : output/results/sensitivity_own_history.dta
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
local R "${out}/results"

use "${data}/NGMS_ENV_ready_2026_09_13.dta", clear
merge m:1 firm_name year using "`R'/firm_year_ngms_s1_s2.dta", assert(match) nogenerate keepusing(phi)
egen estab_id = group(firm_name est_name)
egen fy_id = group(firm_name year)
gen byte rep1 = !missing(est_emission_scope1) & energy > 0
gen byte rep2 = !missing(est_emission_scope2) & energy > 0
gen double I1 = est_emission_scope1 / energy if rep1
gen double I2 = est_emission_scope2 / energy if rep2
* leak-free firm fallback: scope intensity of the firm's other establishments reporting both scopes
* (same year, else the firm's other years, else the global median of cell intensities)
gen byte both = rep1 & rep2
bys fy_id: egen double U_fy = total(cond(both, energy, 0))
bys firm_name: egen double U_f = total(cond(both, energy, 0))
gen double ownU = cond(both, energy, 0)
foreach g in 1 2 {
    bys fy_id: egen double E`g'_fy = total(cond(both, est_emission_scope`g', 0))
    bys firm_name: egen double E`g'_f = total(cond(both, est_emission_scope`g', 0))
    gen double own`g' = cond(both, est_emission_scope`g', 0)
    gen double t2_`g' = (E`g'_fy - own`g') / (U_fy - ownU) if (U_fy - ownU) > 0
    replace t2_`g' = (E`g'_f - own`g') / (U_f - ownU) if t2_`g' == . & (U_f - ownU) > 0
    gen double Ik`g' = est_emission_scope`g' / energy if both
    quietly summarize Ik`g', detail
    replace t2_`g' = r(p50) if t2_`g' == .
}
bys fy_id: egen double F1 = total(cond(rep1, est_emission_scope1, 0))
bys fy_id: egen double F2 = total(cond(rep2, est_emission_scope2, 0))
gen double Ftot = F1 + F2
keep if rep1 | rep2
keep estab_id fy_id year energy I1 I2 est_emission_scope1 est_emission_scope2 t2_1 t2_2 Ftot rep1 rep2
tempfile base
save `base', replace
keep estab_id year I1 I2
rename year yr
rename I1 J1
rename I2 J2
tempfile trn
save `trn', replace
use `base', clear
joinby estab_id using `trn'
gen d = abs(year - yr)
drop if d == 0
tempfile pairs
save `pairs', replace

* variants: name nn b bgap bmin  (b = 0 means unbounded; bgap/bmin as in allocate_joint)
local V1  "nn3_none 3 0 0 0"
local V2  "nn3_b2 3 2 0 0"
local V3  "nn3_b3 3 3 0 0"
local V4  "nn3_b5 3 5 0 0"
local V5  "nn3_b10 3 10 0 0"
local V6  "nn3_b3_cond 3 3 2 3"
local V7  "nn3_b5_cond 3 5 2 3"
local V8  "nn1_b3 1 3 0 0"
local V9  "nn5_b3 5 3 0 0"
local nvar 9
tempname r
postfile r str12 variant byte k byte g double(n_cells share_avail medape_own medape_t2 mae_own mae_t2) using "`R'/sensitivity_own_history.dta", replace
foreach k in 1 2 3 4 6 8 {
    forvalues i = 1/`nvar' {
        tokenize `V`i''
        local vname `1'
        local nn `2'
        local b `3'
        local bgap `4'
        local bmin `5'
        use `pairs', clear
        keep if d >= `k'
        foreach g in 1 2 {
            gen double dd`g' = cond(J`g' != ., d + 0.001 * (yr > year), .)
            bys estab_id year (dd`g'): gen rk`g' = _n if J`g' != .
            gen double sel`g' = J`g' if rk`g' <= `nn'
            gen double gp`g' = d if rk`g' == 1
            gen byte ct`g' = rk`g' <= `nn'
        }
        collapse (median) own1 = sel1 own2 = sel2 (min) gap1 = gp1 gap2 = gp2 (sum) n1 = ct1 n2 = ct2, by(estab_id year)
        merge 1:1 estab_id year using `base', nogenerate
        foreach g in 1 2 {
            quietly count if rep`g'
            local ncell = r(N)
            gen double Iown = own`g' if rep`g'
            if `b' > 0 {
                gen byte dob = (gap`g' > `bgap' | n`g' < `bmin') if Iown != .
                replace Iown = min(max(own`g', t2_`g' / `b'), `b' * t2_`g') if Iown != . & t2_`g' > 0 & dob
                drop dob
            }
            gen double pred_own = Iown * energy if rep`g'
            gen double pred_t2  = t2_`g' * energy if rep`g'
            gen double ape_own = abs(pred_own - est_emission_scope`g') / est_emission_scope`g' if rep`g' & est_emission_scope`g' > 0 & pred_own != .
            gen double ape_t2  = abs(pred_t2  - est_emission_scope`g') / est_emission_scope`g' if rep`g' & est_emission_scope`g' > 0 & pred_own != .
            gen double e_own = abs(pred_own - est_emission_scope`g') / Ftot if rep`g' & pred_own != .
            gen double e_t2  = abs(pred_t2  - est_emission_scope`g') / Ftot if rep`g' & pred_own != .
            quietly count if rep`g' & pred_own != .
            local avail = r(N) / `ncell'
            quietly summarize ape_own, detail
            local mo = r(p50)
            quietly summarize ape_t2, detail
            local mt = r(p50)
            quietly summarize e_own, meanonly
            local eo = r(mean)
            quietly summarize e_t2, meanonly
            local et = r(mean)
            post r ("`vname'") (`k') (`g') (`ncell') (`avail') (`mo') (`mt') (`eo') (`et')
            drop Iown pred_own pred_t2 ape_own ape_t2 e_own e_t2
        }
    }
}
postclose r
use "`R'/sensitivity_own_history.dta", clear
label var share_avail "Share of reported cells with own history at least k years away"
label var medape_own  "Median APE of the own-history prediction"
label var medape_t2   "Median APE of the firm-level fallback on the same cells"
label var mae_own     "Mean absolute error / firm-year total, own-history prediction"
label var mae_t2      "Mean absolute error / firm-year total, firm-level fallback"
sort g variant k
save "`R'/sensitivity_own_history.dta", replace
format %5.3f share_avail medape_own medape_t2
format %6.4f mae_own mae_t2
list g variant k share_avail medape_own medape_t2 mae_own mae_t2, noobs sepby(g variant)
display as text "3c_parameter_sensitivity complete."
