# Evidence of Limited Correspondence between Environmental Social and Governance Scores and Future Corporate Carbon Damages

## Overview
This repository provides the data and code required to replicate the figures and tables in our paper. The scripts included here reproduce all reported results, conditional on access to the underlying datasets. Additional scripts developed for processing and integrating the licensed firm-level financial and ESG datasets are not publicly available, as they contain dataset-specific preprocessing routines that depend on the structure of restricted data. However, should permission be obtained from all relevant data providers, the authors will make these data available upon request.


## Software
Stata 18

## Data

### Opened Datasets

#### Social Cost of Carbon
* U.S. Environmental Protection Agency

#### GHG Emissions
* National GHG Management System

### Restricted-Access Datasets

#### ESG Scores
* Sustinvest
* KCGS
* MSCI
* Refinitiv

#### Firm-Level Financial Data
* VALUE Search

## File Description

### dta File
* **EPA_SCC.dta**

   It contains the Social Cost of Carbon at discount rates of 1.5%, 2.0%, and 2.5% through 2100.
* **NGMS_Emission_restricted.dta**

   It contains firm name (in Korean), firm ID, year, and GHG emissions from 2011 to 2023.
* **Other dta files will be provided after authorization.**

### do File
* **Figure1_a**

   This code replicates Panel (a) in Figure 1.
  
* **Other do files will be provided after authorization.**
   
## Replication Instructions

**Set the directory and run the do file as follows.**
* **Set the directory**

   global directory "/Users/kyle/Library/CloudStorage/Dropbox/Carbon Burden/Replication Package"

   global data = "${directory}/data"

   global code = "${directory}/code"

* **Run do file**

   do "${code}/figure1_a.do"
