/*
1a_firm_decomp_s1_s2.do

Decompose the NGMS firm-year total (emission_ngms = scope 1 + scope 2) into
firm-year scope 1 and scope 2 totals using the scope-1 SHARE observed in
ENV-Info establishment reports:

    phi_ft  = ENV S1_ft / (ENV S1_ft + ENV S2_ft)
    NGMS_S1 = phi_ft * emission_ngms,    NGMS_S2 = (1 - phi_ft) * emission_ngms

Only the share is borrowed from ENV-Info; levels come entirely from NGMS, so
NGMS_S1 + NGMS_S2 = emission_ngms by construction and partial reporting in
ENV-Info cannot distort the level.

phi is filled by a four-step rule (phi_source):
  1 observed   all establishments report both scopes and the ENV total is within
               +/- gate_tol (15%) of the NGMS total
  2 own_firm   linear interpolation of the firm's step-1 shares across years
               (nearest value beyond the first/last step-1 year)
  3 partial    firms with no step-1 year: share among establishments reporting
               both scopes, if they cover >= 30% of firm-year energy and the ENV
               total is 5-115% of NGMS; interpolated across years as in step 2
  4 cell       mean step-1 share in the KSIC 2-digit division x emission-intensity
               tercile cell; if unsupported (< 5 firm-years): KSIC section,
               then the FIRE group (sections K + L), then building-based services
               (sections G, J, K, L, M, N), then the global mean.
               Industry is the firm-level KSIC code from NGMS (data/firm_info.dta),
               fixed over time.

Firm-year scope totals (actual-first at the firm-scope level):
  phi estimates the scope-1 share of the part of the firm's NGMS total that is NOT
  covered by ENV-Info reports. With S1_sub, S2_sub the reported subtotals over all
  reporting establishments and R = max(NGMS - S1_sub - S2_sub, 0) the unreported
  residual,
      NGMS_S1 = S1_sub + R1,  NGMS_S2 = S2_sub + R2,   R1 + R2 = R,
  where R1 = phi * R when both scopes have missing establishments, R1 = R when only
  scope 1 has missing establishments, R1 = 0 when only scope 2 does (and R1 = phi * R
  when no establishment is missing, so that firm totals still add up to NGMS).
  Reported subtotals are therefore never overridden and NGMS_S1 + NGMS_S2 = NGMS.
  Feasibility: if S1_sub + S2_sub exceeds NGMS by more than 2% the reported values
  cannot both be right; the firm-year is flagged (phi_conflict = 1), the split falls
  back to phi * NGMS, and the allocation step leaves the affected missing
  establishments unfilled instead of imputing zero.
  phi_bound_gap records how far the estimated share phi lies outside the interval
  [S1_sub / NGMS, 1 - S2_sub / NGMS] implied by the reported subtotals (diagnostic).

Validation (step-1 firm-years, output/results/decompose_validation.dta):
  A  own-firm interpolation, leave-one-year-out   (accuracy of step 2)
  C  cell mean, leave-one-firm-out                 (accuracy of step 4)
Gate sensitivity (10% / 15% / 20%): output/results/decompose_gate_sensitivity.dta

Input : data/NGMS_ENV_ready_2026_09_13.dta
Output: output/results/firm_year_ngms_s1_s2.dta
        output/results/decompose_validation.dta
        output/results/decompose_gate_sensitivity.dta
        output/results/decompose_source_summary.dta
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

local ready     "NGMS_ENV_ready_2026_09_13"
local gate_main 0.15
local gate_list "0.10 0.15 0.20"
local sub_min   0.30
local sub_lo    0.05
local sub_hi    1.15
local mincell   5
local feas_tol  0.02      // rounding tolerance for the feasibility test S1_sub + S2_sub <= NGMS
local fire      "K L"            // KSIC sections: K finance & insurance, L real estate
local bldg      "G J K L M N"    // building-based services: retail, ICT, finance, real estate, professional, support

capture confirm file "${data}/`ready'.dta"
if _rc {
    display as error "Cannot find data/`ready'.dta."
    exit 601
}

* ---------------------------------------------------------------------------
* 1. Establishment level -> firm-year level
* ---------------------------------------------------------------------------
use "${data}/`ready'.dta", clear
isid firm_name est_name year

gen byte   both    = !missing(est_emission_scope1) & !missing(est_emission_scope2)
gen double s1b     = cond(both, est_emission_scope1, 0)
gen double s2b     = cond(both, est_emission_scope2, 0)
gen byte   rep1    = !missing(est_emission_scope1)
gen byte   rep2    = !missing(est_emission_scope2)
gen double s1_all  = cond(missing(est_emission_scope1), 0, est_emission_scope1)
gen double s2_all  = cond(missing(est_emission_scope2), 0, est_emission_scope2)
gen double en_all  = cond(missing(energy), 0, energy)
gen double en_both = cond(both & !missing(energy), energy, 0)
gen byte   one     = 1

* firm industry = firm-level KSIC from NGMS (ksic1 section, ksic2 division), fixed over time
assert !missing(ksic_sec) & !missing(ksic2)
gen str8 ind1_firm = ksic_sec
gen str8 ind2_firm = string(ksic2)

collapse (sum) K = one n_both = both n1 = rep1 n2 = rep2 s1b s2b s1_all s2_all en_all en_both ///
         (first) emission_ngms ind1_firm ind2_firm, by(firm_name year)
isid firm_name year
assert !missing(emission_ngms) & emission_ngms > 0

gen byte   complete  = (n_both == K)
gen double env_total = s1b + s2b
gen double env_ratio = env_total / emission_ngms
gen double phi_raw   = s1b / env_total if env_total > 0
gen double sub_energy_share = en_both / en_all if en_all > 0
gen double intensity = emission_ngms / en_all if en_all > 0
xtile int3 = intensity, nq(3)
gen byte fire = 0
foreach s of local fire {
    replace fire = 1 if ind1_firm == "`s'"
}
gen byte bldg = 0
foreach s of local bldg {
    replace bldg = 1 if ind1_firm == "`s'"
}
label var complete  "All establishments report both scopes"
label var env_ratio "ENV (S1+S2) / NGMS"
label var phi_raw   "ENV S1 share among both-scope reporters"
label var sub_energy_share "Energy share of establishments reporting both scopes"

tempfile fy
save `fy', replace

* ---------------------------------------------------------------------------
* 2. Helper: within-firm linear interpolation across years
*    syntax: interp_years srcvar newvar distvar
* ---------------------------------------------------------------------------
capture program drop interp_years
program define interp_years
    args src new dist
    tempfile tbl
    preserve
        keep if !missing(`src')
        keep firm_name year `src'
        rename year year_m
        rename `src' v_m
        save `tbl', replace
    restore
    gen double vb = .
    gen byte   db = .
    gen double va = .
    gen byte   da = .
    forvalues d = 1/11 {
        gen year_m = year - `d'
        merge m:1 firm_name year_m using `tbl', keep(master match) nogenerate
        replace vb = v_m if missing(vb) & !missing(v_m)
        replace db = `d' if missing(db) & !missing(vb)
        drop year_m v_m
        gen year_m = year + `d'
        merge m:1 firm_name year_m using `tbl', keep(master match) nogenerate
        replace va = v_m if missing(va) & !missing(v_m)
        replace da = `d' if missing(da) & !missing(va)
        drop year_m v_m
    }
    gen double `new' = cond(!missing(vb, va), (vb * da + va * db) / (da + db), ///
                        cond(!missing(vb), vb, va))
    gen byte `dist' = cond(!missing(vb, va), min(db, da), cond(!missing(vb), db, da))
    drop vb db va da
end

* ---------------------------------------------------------------------------
* 3. Helper: build phi for a given gate tolerance
*    syntax: build_phi tol   (data in memory = firm-year base; adds phi phi_source ...)
* ---------------------------------------------------------------------------
capture program drop build_phi
program define build_phi
    args tol
    gen byte   gate    = complete & inrange(env_ratio, 1 - `tol', 1 + `tol')
    gen double phi_obs = phi_raw if gate
    bys firm_name: egen byte firm_has_obs = max(gate)
    gen double phi_sub = phi_raw if !gate & !firm_has_obs & n_both > 0 ///
        & sub_energy_share >= ${sub_min} & inrange(env_ratio, ${sub_lo}, ${sub_hi})

    interp_years phi_obs phi_own dist_own
    interp_years phi_sub phi_par dist_par

    * step-4 cells from step-1 shares
    egen cell2 = group(ind2_firm int3)
    bys cell2: egen double c2_sum = total(phi_obs)
    bys cell2: egen        c2_n   = count(phi_obs)
    bys ind1_firm: egen double c1_sum = total(phi_obs)
    bys ind1_firm: egen        c1_n   = count(phi_obs)
    gen double fire_obs = phi_obs if fire
    egen double cf_sum = total(fire_obs)
    egen        cf_n   = count(fire_obs)
    gen double bldg_obs = phi_obs if bldg
    egen double cb_sum = total(bldg_obs)
    egen        cb_n   = count(bldg_obs)
    quietly summarize phi_obs, meanonly
    local g = r(mean)
    gen double phi_cell = c2_sum / c2_n if c2_n >= ${mincell}
    gen byte   cell_kind = 1 if !missing(phi_cell)
    replace phi_cell = c1_sum / c1_n if missing(phi_cell) & c1_n >= ${mincell}
    replace cell_kind = 2 if missing(cell_kind) & !missing(phi_cell)
    replace phi_cell = cf_sum / cf_n if missing(phi_cell) & fire & cf_n >= ${mincell}
    replace cell_kind = 3 if missing(cell_kind) & !missing(phi_cell)
    replace phi_cell = cb_sum / cb_n if missing(phi_cell) & bldg & cb_n >= ${mincell}
    replace cell_kind = 4 if missing(cell_kind) & !missing(phi_cell)
    replace phi_cell = `g' if missing(phi_cell)
    replace cell_kind = 5 if missing(cell_kind)

    gen double phi = .
    gen byte   phi_source = .
    replace phi = phi_obs  if !missing(phi_obs)
    replace phi_source = 1 if !missing(phi_obs)
    replace phi = phi_own  if missing(phi) & !missing(phi_own)
    replace phi_source = 2 if missing(phi_source) & !missing(phi)
    replace phi = phi_par  if missing(phi) & !missing(phi_par)
    replace phi_source = 3 if missing(phi_source) & !missing(phi)
    replace phi = phi_cell if missing(phi)
    replace phi_source = 4 if missing(phi_source)
    assert inrange(phi, 0, 1)
    drop c2_sum c2_n c1_sum c1_n fire_obs cf_sum cf_n bldg_obs cb_sum cb_n cell2
end

global sub_min   `sub_min'
global sub_lo    `sub_lo'
global sub_hi    `sub_hi'
global mincell   `mincell'
global feas_tol  `feas_tol'

* ---------------------------------------------------------------------------
* 3b. Helper: firm-year scope totals = reported subtotals + split of the unreported residual
* ---------------------------------------------------------------------------
capture program drop split_residual
program define split_residual
    * feasibility of the reported subtotals against the NGMS total
    gen double phi_lb = min(s1_all / emission_ngms, 1)
    gen double phi_ub = max(1 - s2_all / emission_ngms, 0)
    gen byte   phi_conflict = (s1_all + s2_all) > (1 + ${feas_tol}) * emission_ngms
    gen double phi_bound_gap = max(phi_lb - phi, phi - phi_ub, 0)
    * unreported residual and its split across scopes
    gen byte   miss1 = n1 < K
    gen byte   miss2 = n2 < K
    gen double r_tot = max(emission_ngms - s1_all - s2_all, 0)
    gen double R1 = cond(miss1 & !miss2, r_tot, cond(!miss1 & miss2, 0, phi * r_tot))
    gen double R2 = r_tot - R1
    gen double NGMS_S1 = s1_all + R1
    gen double NGMS_S2 = s2_all + R2
    * inconsistent reports: fall back to the estimated split of the NGMS total
    replace NGMS_S1 = phi * emission_ngms if phi_conflict
    replace NGMS_S2 = emission_ngms - NGMS_S1 if phi_conflict
    gen double phi_eff = NGMS_S1 / emission_ngms
    * identity holds exactly unless reported subtotals exceed NGMS within the rounding tolerance
    assert abs(NGMS_S1 + NGMS_S2 - emission_ngms) <= ${feas_tol} * emission_ngms + 1e-6
    assert abs(NGMS_S1 + NGMS_S2 - emission_ngms) < 1e-6 * emission_ngms if r_tot > 0 | phi_conflict
    assert NGMS_S1 >= -1e-9 & NGMS_S2 >= -1e-9
end

* ---------------------------------------------------------------------------
* 4. Main build (gate = 15%)
* ---------------------------------------------------------------------------
use `fy', clear
build_phi `gate_main'
split_residual
label var phi_conflict  "1 if reported S1 + S2 subtotals exceed the NGMS total beyond tolerance"
label var phi_bound_gap "Distance of phi outside the interval implied by reported subtotals (0 = inside)"
label var phi_eff       "Effective scope 1 share of the NGMS total (NGMS_S1 / NGMS)"
label var r_tot         "Unreported residual: NGMS - reported S1 - reported S2 (floored at 0)"

label define phi_source_lbl 1 "observed" 2 "own_firm" 3 "partial" 4 "cell", replace
label values phi_source phi_source_lbl
replace cell_kind = . if phi_source != 4
label define cell_kind_lbl 1 "ksic2 x intensity" 2 "ksic section" 3 "FIRE" 4 "building services" 5 "global", replace
label values cell_kind cell_kind_lbl

label var phi        "Estimated scope 1 share of the unreported residual (four-step rule)"
label var phi_source "Source of phi: 1 observed, 2 own-firm interpolation, 3 partial, 4 cell"
label var cell_kind  "Cell used when phi_source == 4"
label var NGMS_S1    "Firm-year NGMS scope 1 total (decomposed), tCO2eq"
label var NGMS_S2    "Firm-year NGMS scope 2 total (decomposed), tCO2eq"

tempfile main
save `main', replace

* ---------------------------------------------------------------------------
* 5. Validation on step-1 firm-years: A (own-firm LOYO), C (cell LOFO)
* ---------------------------------------------------------------------------
* A: phi_own is already computed from OTHER years only (distance >= 1)
gen double errA = abs(phi_own - phi_obs) if phi_source == 1
* C: leave-one-firm-out cell mean (ind2 x intensity)
egen cell2 = group(ind2_firm int3)
bys cell2: egen double c_sum = total(phi_obs)
bys cell2: egen        c_n   = count(phi_obs)
bys cell2 firm_name: egen double cf_sum = total(phi_obs)
bys cell2 firm_name: egen        cf_n   = count(phi_obs)
gen double phi_cell_lofo = (c_sum - cf_sum) / (c_n - cf_n) if (c_n - cf_n) >= `mincell'
gen double errC = abs(phi_cell_lofo - phi_obs) if phi_source == 1
foreach m in A C {
    quietly summarize err`m', detail
    local N_`m' = r(N)
    local mae_`m' = r(mean)
    local med_`m' = r(p50)
    local p90_`m' = r(p90)
}
preserve
    clear
    set obs 2
    gen str48 method = ""
    replace method = "A own-firm interpolation (leave-one-year-out)" in 1
    replace method = "C cell mean, KSIC 2-digit x intensity (LOFO)" in 2
    gen N = .
    gen double MAE = .
    gen double medianAE = .
    gen double p90AE = .
    local i = 1
    foreach m in A C {
        replace N = `N_`m'' in `i'
        replace MAE = `mae_`m'' in `i'
        replace medianAE = `med_`m'' in `i'
        replace p90AE = `p90_`m'' in `i'
        local ++i
    }
    save "${out}/results/decompose_validation.dta", replace
    list, noobs
restore

* ---------------------------------------------------------------------------
* 6. Source summary
* ---------------------------------------------------------------------------
preserve
    gen one = 1
    collapse (count) firm_years = one (sum) ngms_total = emission_ngms, by(phi_source cell_kind)
    egen double tot_fy = total(firm_years)
    egen double tot_ngms = total(ngms_total)
    gen double share_fy   = firm_years / tot_fy
    gen double share_ngms = ngms_total / tot_ngms
    drop tot_fy tot_ngms
    save "${out}/results/decompose_source_summary.dta", replace
    list, noobs
restore
preserve
    gen one = 1
    gen byte gap_gt_005 = phi_bound_gap > 0.05
    collapse (count) firm_years = one (sum) ngms_total = emission_ngms gap_gt_005 (mean) mean_gap = phi_bound_gap, by(phi_conflict)
    save "${out}/results/decompose_bound_summary.dta", replace
    list, noobs
restore

* ---------------------------------------------------------------------------
* 7. Gate sensitivity (10 / 15 / 20 %)
* ---------------------------------------------------------------------------
use `main', clear
keep firm_name year NGMS_S1
rename NGMS_S1 s1_main
tempfile ref
save `ref', replace

clear
set obs 0
gen double gate_tol = .
gen step1_fy = .
gen double step1_ngms_share = .
gen double loyo_mae = .
gen double agg_s1_share = .
gen double mean_abs_change_vs_main = .
tempfile sens
save `sens', replace

foreach tol of local gate_list {
    use `fy', clear
    build_phi `tol'
    split_residual
    gen double errA = abs(phi_own - phi_obs) if phi_source == 1
    quietly summarize errA, meanonly
    local mae = r(mean)
    quietly count if phi_source == 1
    local n1 = r(N)
    quietly summarize emission_ngms, meanonly
    local tot = r(sum)
    quietly summarize emission_ngms if phi_source == 1, meanonly
    local share1 = r(sum) / `tot'
    quietly summarize NGMS_S1, meanonly
    local agg = r(sum) / `tot'
    merge 1:1 firm_name year using `ref', nogenerate
    gen double chg = abs(NGMS_S1 - s1_main) / s1_main if s1_main > 0
    quietly summarize chg, meanonly
    local chg = r(mean)
    clear
    set obs 1
    gen double gate_tol = `tol'
    gen step1_fy = `n1'
    gen double step1_ngms_share = `share1'
    gen double loyo_mae = `mae'
    gen double agg_s1_share = `agg'
    gen double mean_abs_change_vs_main = `chg'
    append using `sens'
    save `sens', replace
}
use `sens', clear
sort gate_tol
save "${out}/results/decompose_gate_sensitivity.dta", replace
list, noobs

* ---------------------------------------------------------------------------
* 8. Save main output
* ---------------------------------------------------------------------------
use `main', clear
keep firm_name year emission_ngms NGMS_S1 NGMS_S2 phi phi_eff phi_source cell_kind phi_conflict phi_bound_gap r_tot s1_all s2_all n1 n2 ///
     K n_both complete env_ratio gate phi_raw sub_energy_share dist_own dist_par ///
     ind1_firm ind2_firm int3 fire
order firm_name year emission_ngms NGMS_S1 NGMS_S2 phi phi_eff phi_source cell_kind phi_conflict
compress
save "${out}/results/firm_year_ngms_s1_s2.dta", replace
display as text "1a complete: ${out}/results/firm_year_ngms_s1_s2.dta"
