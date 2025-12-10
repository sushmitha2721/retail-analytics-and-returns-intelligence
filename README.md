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
**Sales Classification**
  
Sales transactions were grouped into:
- Product, service, adjustment
  
- Shipping fees, paid/free samples, manual corrections
  
- Revenue vs non-revenue vs fee

This gives sales data clear business meaning.

**Returns Classification**

A custom rule-based returns intelligence system classifies returns by:

- **Return Type** (cancellation, damaged goods, system return, service return, customer return, price adjustment)

- **Return Reason** (defective, shipping error, suspicious discount, high-value return, order cancellation, frequent returner, etc.)

- **Refund Status** (processed, pending, pending_review, fraud_review, review_required)

This converts raw return data into operational insights.

## 3️⃣ Analytics Modules
**Sales Analytics**

- Monthly revenue trends

- Top-selling products

- Revenue by country

- Product return rates

**Returns Analytics**

- Total return quantity and value

- Return type breakdown

- Return reason × refund status matrix

- Most returned products

- Returns by country

**Customer Analytics**

- Customer lifetime value (LTV)

- Repeat purchase behaviour

- Retention vs churn

- Monthly active customers

- Customer profitability by country

## 📊 Key Results (Insights)

**Sales Insights**

- Revenue follows strong seasonal patterns.

- Top products contribute most of the revenue.

- Several products show unusually high return rates

**Returns Insights**

- Customer returns form the majority of return volume.

- High-value returns and suspicious discounts were detected automatically.

- Damaged, defective, and shipping-related returns appear consistently.

**Customer Insights**

- A small number of customers generate most of the revenue.

- Repeat purchase behaviour is low → churn issue.

- Monthly active customer trends align with seasonal demand peaks.
