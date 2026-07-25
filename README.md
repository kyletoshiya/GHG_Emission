# Firm-Establishment Matched Carbon Emissions Data in South Korea from 2011 to 2023

## Overview
This repository provides the data and code required to replicate the figures and tables in our paper. The scripts included here reproduce all reported results.


## Software
Stata 18

## Data

### National Greenhouse Gas Management System (NGMS)
NGMS provides **annual GHG emissions data from 2011 to 2023 for firms** participating in the Emissions Trading Scheme (ETS) and the Target Management System (TMS). ETS covers firms that meet at least one of the following three criteria: (a) have averaged more than 125,000 tCO₂-eq in annual GHG emissions over the past three years; (b) operate at least one establishment with annual average emissions exceeding 25,000 tCO₂-eq; or (c) voluntarily apply (Act on the Allocation and Trading of Greenhouse-Gas Emission Permits, No.20229). TMS covers firms that meet at least one of the following two criteria: (a) have averaged more than 50,000 tCO₂-eq in annual GHG emissions over the past three years; or (b) operate at least one establishment with annual average emissions exceeding 15,000 tCO₂-eq (Framework Act on Carbon Neutrality and Green Growth for Coping with Climate Crisis, No. 20849).

Source: [National Greenhouse Gas Management System (NGMS)](https://ngms.gir.go.kr:8443/subMain.do?link=/hom/bbs/OGCMBBS023V.xml&menuNo=50900503)

### Environmental Information Disclosure System (ENV-Info)
Under Article 16-8 of the Environmental Technology and Industry Support Act, public institutions prescribed by Presidential Decree and establishements with significant environmental effects are required to prepare and disclose their environmental information. Establishments in this system are required to report not only environmental information but also general information about the firm. Accordingly, this dataset includes environmental variables such as **GHG emissions (Scope 1), GHG emissions (Scope 2), water use, energy use, waste generation, and chemical use**, as well as establishment-level variables such as **industry, address, number of employees, revenue, and product**.

Source: [Environmental Information Disclosure System (ENV-Info)](https://www.env-info.kr/)

## File Description

### dta File
* **NGMS_ENV_matched.dta**
  
   This dataset was constructed by matching firm-level data from NGMS with establishment-level data from ENV-Info. It represents the raw data before any missing values were imputed.

* **NGMS_ENV_estimated.dta**
  
   This dataset provides estimates of GHG emissions for establishments, based on their energy use.


  #### ▸ Variables List and Description


    | Variable | Description | Unit |
    |---|---|---|
    | `firm_name` | Firm name | — |
    | `est_name` | Establishment name | — |
    | `year` | Year | — |
    | `emission_ngms` | Firm-level GHG emissions reported to NGMS | tCO₂-eq |
    | `est_emission_scope1` | Establishment-level direct GHG emissions (Scope 1) | tCO₂-eq |
    | `est_emission_scope2` | Establishment-level indirect GHG emissions from purchased energy (Scope 2) | tCO₂-eq |
    | `industry` | Industry classification | — |
    | `sub_industry` | Sub-industry classification | — |
    | `address` | Establishment address | — |
    | `employee` | Number of employees | persons |
    | `revenue` | Firm revenue | KRW million |
    | `product` | Main product(s) produced | — |
    | `water` | Water use | ton |
    | `energy` | Energy use | TJ |
    | `waste` | Waste generation | ton |
    | `chemicals` | Chemical use | ton |
    | `sido` | Province-level administrative division (Sido) | — |
    | `sigungu` | County-level administrative division (Sigungu) | — |
    | `emi_s1_firm` | NGMS-reported firm-level Scope 1 total | tCO₂-eq |
    | `emi_s1_estab` | Final Scope 1 establishment-level emissions | tCO₂-eq |
    | `emi_s1_src` | Source of `emi_s1_estab`: 0 = actual, 1 = estimated, missing = unfilled | — |
    | `emi_s2_firm` | Predicted firm-level Scope 2 total | tCO₂-eq |
    | `emi_s2_estab` | Final Scope 2 establishment-level emissions | tCO₂-eq |
    | `emi_s2_src` | Source of `emi_s2_estab`: 0 = actual, 1 = estimated, missing = unfilled | — |



* **NGMS_ENV_county.dta**
  This dataset uses **NGMS_ENV_estimated.dta** to aggregate GHG emissions at the county level. It illustrates the difference between aggregating at the firm level versus aggregating at the establishment level.
   
  #### ▸ Variables List and Description


    | Variable | Description | Unit |
    |---|---|---|
    | `est_emission_scope1` | Establishment-level direct GHG emissions (Scope 1) | tCO₂-eq |
    | `est_emission_scope2` | Establishment-level indirect GHG emissions from purchased energy (Scope 2) | tCO₂-eq |
    | `water` | Water use | ton |
    | `energy` | Energy use | TJ |
    | `waste` | Waste generation | ton |
    | `chemicals` | Chemical use | ton |
    | `industry` | Industry classification | — |
    | `sub_industry` | Sub-industry classification | — |
    | `address` | Establishment address | — |
    | `employee` | Number of employees | persons |
    | `revenue` | Firm revenue | KRW million |
    | `product` | Main product(s) produced | — |


### do File
* **Figure1_a**

   This code replicates Panel (a) in Figure 1.
  

## Replication Instructions

**Set the directory and run the do file as follows.**

* **Set the directory**

> ⚠️ **`global main = "PUT YOUR DIRECTORY"`**
global dofile ="${main}/dofile"

* **Run do file**

do "${dofile}/scope1_estimation.do"
do "${dofile}/scope2_estimation.do"
do "${dofile}/construct_final.do"
