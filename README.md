# 🛒 Retail Analytics & Returns Intelligence System
## End-to-End Python ETL + MySQL Data Analytics Project

## 📌 Overview
The Retail Analytics & Returns Intelligence System transforms raw retail transaction data into a clean, structured, and analytics-ready dataset that reveals insights about sales performance, customer behaviour, product patterns, and return activity.

The system combines a Python ETL pipeline for data cleaning and standardization with SQL classification models that categorize sales and returns into meaningful business concepts. Analytical SQL modules then calculate trends, behaviors, and operational indicators across the retail dataset.

This project showcases practical skills in Python, SQL, data cleaning, business intelligence, and analytical storytelling.

## 🎯 Objective

The objective of this project is to convert messy raw retail data into a structured, intelligent dataset that supports decision-making across sales, product performance, customer behaviour, and return activity.

The goals include:

- Standardizing and cleaning product descriptions using fuzzy matching

- Recovering missing or inconsistent customer information

- Categorizing sales and returns into meaningful business groups

- Building a return-intelligence layer to detect cancellations, damaged goods, shipping issues, system errors, high-value returns, and suspicious discount activity

- Generating insights about revenue trends, return patterns, and customer behaviour

## 🔧 What We Did (Methodology)

## 1️⃣ Python ETL Pipeline (etl.py)
The ETL pipeline:
- Loaded the raw CSV dataset

- Cleaned dates and numerical fields

- Recovered missing CustomerIDs using invoice-based inference

- Tagged customers as Guest or Registered

- Cleaned and normalized product descriptions

- Used fuzzy matching to combine similar item descriptions

- Created canonical clean descriptions (Description_clean)

- Added derived fields such as Order_Value and customer type

- Wrote cleaned data into MySQL in efficient chunks
  This produced the foundational table: clean_transactions.

  ## 2️⃣ SQL Classification Models
  ** Sales Classification **
Sales transactions were grouped into:
- Product, service, adjustment
  
- Shipping fees, paid/free samples, manual corrections
  
- Revenue vs non-revenue vs fee
This gives sales data clear business meaning.



