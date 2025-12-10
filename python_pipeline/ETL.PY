import pandas as pd
import numpy as np
from itertools import combinations
from rapidfuzz import fuzz
import sqlite3
import os
from sqlalchemy import create_engine
import mysql.connector
from urllib.parse import quote_plus


# =========================
# 1. LOADING & BASIC CLEANING
# =========================

def load_transactions(csv_path: str) -> pd.DataFrame:
    """Load raw CSV and parse InvoiceDate."""
    df = pd.read_csv(
        csv_path,
        parse_dates=['InvoiceDate'],
        dayfirst=False,
        encoding='latin1'
    )
    df['InvoiceDate'] = pd.to_datetime(df['InvoiceDate'], dayfirst=True, errors='coerce')
    return df


def fix_customer_ids(df: pd.DataFrame) -> pd.DataFrame:
    """
    - Infer CustomerID from other rows on same InvoiceNo
    - Remaining nulls → 0 (Guest)
    - Adds 'Customertype'
    """
    df = df.copy()

    # Mapping InvoiceNo -> CustomerID from non-null rows
    invoice_to_customer = (
        df.dropna(subset=['CustomerID'])
          .groupby('InvoiceNo')['CustomerID']
          .first()
    )

    # Fill via invoice mapping
    df['CustomerID'] = df['CustomerID'].fillna(df['InvoiceNo'].map(invoice_to_customer))

    # Remaining nulls -> 0 (guest)
    df['CustomerID'] = df['CustomerID'].fillna(0).astype(int)

    # Customer type
    df['Customertype'] = np.where(df['CustomerID'] == 0, 'Guest', 'Registered')

    return df


def add_order_value(df: pd.DataFrame) -> pd.DataFrame:
    """Add Order_Value = Quantity * UnitPrice."""
    df = df.copy()
    df['Order_Value'] = df['Quantity'] * df['UnitPrice']
    return df


# =========================
# 2. DESCRIPTION CLEANING
# =========================

def normalize_descriptions(df, source_col='Description'):
    """
    - Fill NaNs with empty string
    - Lowercase, trim, collapse whitespace
    - Creates column 'desc_norm'
    """
    df['desc_norm'] = (
        df[source_col]
          .fillna('')
          .str.lower()
          .str.strip()
          .str.replace(r'\s+', ' ', regex=True)
    )
    return df


def cluster_variants(variants, thresh=90):
    """
    Group similar text variants (token_sort_ratio >= thresh).
    Returns dict mapping each variant -> cluster representative (longest text).
    """
    clusters, assigned = [], set()
    for a, b in combinations(variants, 2):
        if a in assigned and b in assigned:
            continue
        if fuzz.token_sort_ratio(a, b) >= thresh:
            # merge into existing cluster
            for cl in clusters:
                if a in cl or b in cl:
                    cl.update({a, b})
                    break
            else:
                clusters.append({a, b})
            assigned.update([a, b])

    # add any unclustered variants as their own clusters
    for v in variants:
        if v not in assigned:
            clusters.append({v})

    # choose longest string as representative
    rep_map = {}
    for cl in clusters:
        rep = max(cl, key=len)
        for v in cl:
            rep_map[v] = rep
    return rep_map


def build_stockcode_mapping(df, thresh=90):
    """
    For each StockCode with multiple desc_norm values, cluster and map variants.
    Returns mapping: {(StockCode, raw_norm): representative_norm}
    """
    mapping = {}
    for code, grp in df.groupby('StockCode'):
        variants = grp['desc_norm'].dropna().unique().tolist()
        if len(variants) > 1:
            rep_map = cluster_variants(variants, thresh)
            for raw, rep in rep_map.items():
                mapping[(code, raw)] = rep
    return mapping


def apply_canonical(df, mapping):
    """
    - Uses mapping to replace desc_norm with cluster representative
    - If desc_norm is empty, fills with mode of other variants
    - Creates 'Description_final' column (title-cased)
    """
    def get_canonical(row):
        key = (row['StockCode'], row['desc_norm'])
        if key in mapping:
            return mapping[key]
        if not row['desc_norm']:
            # fallback to most common existing desc_norm for that StockCode
            mode_val = (
                df.loc[df['StockCode'] == row['StockCode'], 'desc_norm']
                  .value_counts()
                  .idxmax()
            )
            return mode_val
        return row['desc_norm']

    df['Description_final'] = df.apply(get_canonical, axis=1)
    df['Description_final'] = df['Description_final'].str.title()
    return df


def strip_noise_suffix(df):
    """
    Splits 'Description_final' at first ';' and keeps the core product text in 'desc_core'.
    """
    df['desc_core'] = (
        df['Description_final']
          .str.split(';', n=1)
          .str[0]
          .str.strip()
    )
    return df


def finalize_clean(df):
    """
    Picks the most frequent 'desc_core' per StockCode.
    Creates 'Description_clean' (title-cased, non-null).
    """
    mode_core = (
        df.groupby('StockCode')['desc_core']
          .agg(lambda s: s.value_counts().idxmax())
    )
    df['Description_clean'] = df['StockCode'].map(mode_core)
    df['Description_clean'] = df['Description_clean'].str.title()
    return df


def find_ambiguities(df):
    """
    Returns list of StockCodes with >1 unique 'Description_clean'.
    Just for sanity checking.
    """
    ambiguous = (
        df.groupby('StockCode')['Description_clean']
          .nunique()
          .loc[lambda x: x > 1]
    )
    return list(ambiguous.index)


def impute_missing_description_clean(df):
    """
    Ensures no nulls remain in 'Description_clean'.
    - If null, uses 'desc_core'
    - If still null, uses 'Description_final'
    - If still null, sets to 'Unknown Description'
    """
    df['Description_clean'] = (
        df['Description_clean']
          .fillna(df['desc_core'])
          .fillna(df['Description_final'])
          .fillna('Unknown Description')
    )
    return df


def description_cleaning_pipeline(df: pd.DataFrame) -> pd.DataFrame:
    """
    Runs the full description cleaning pipeline and
    returns df with 'Description_clean' ready to use.
    """
    df = normalize_descriptions(df)
    mapping = build_stockcode_mapping(df)
    df = apply_canonical(df, mapping)
    df = strip_noise_suffix(df)
    df = finalize_clean(df)
    df = impute_missing_description_clean(df)

    ambiguous = find_ambiguities(df)
    print("Ambiguous StockCodes (true variants):", ambiguous)

    # keep original Description, drop helper columns
    df = df.drop(columns=['desc_norm', 'Description_final', 'desc_core'], errors='ignore')

    return df



# =========================
# 3. SAVE CLEANED DATA TO SQL
# =========================
# ---------- MySQL CONNECTION HELPERS ----------

def get_mysql_engine():
    """
    Create a fresh SQLAlchemy engine for MySQL using a URL-encoded password.
    """
    user = "root"
    raw_password = "Example@2022#"      # your real MySQL password
    host = "localhost"
    port = 3306
    database = "inventory"              # make sure this DB exists

    # URL-encode the password so @ and # don't break the URL
    password = quote_plus(raw_password)

    url = f"mysql+mysqlconnector://{user}:{password}@{host}:{port}/{database}"
    engine = create_engine(url, pool_pre_ping=True)
    return engine


def save_to_mysql(df: pd.DataFrame, table_name: str = "clean_transactions"):
    """
    Save cleaned DataFrame to a MySQL database table in smaller chunks
    to avoid 'Lost connection to MySQL server during query' errors.
    """
    engine = get_mysql_engine()
    try:
        chunksize = 5000  # rows per batch; you can tweak this

        print(f"🔄 Writing {len(df):,} rows to MySQL in chunks of {chunksize}...")

        # Use a transaction; each chunk is a smaller INSERT batch
        with engine.begin() as conn:
            df.to_sql(
                table_name,
                conn,
                if_exists="replace",  # drop & recreate table each run
                index=False,
                chunksize=chunksize,  # <= this is the key fix
                method=None,          # let pandas use executemany
            )

        print(f"✅ Saved cleaned data to MySQL: inventory.{table_name}")

    finally:
        engine.dispose()



# =========================
# 4. PIPELINE RUNNER
# =========================
def run_python_cleaning_pipeline(input_csv: str):
    print("Loading raw transactions...")
    transactions = load_transactions(input_csv)

    print("Fixing CustomerID and adding Customertype...")
    transactions = fix_customer_ids(transactions)

    print("Cleaning product descriptions...")
    transactions = description_cleaning_pipeline(transactions)

    print("Adding Order_Value...")
    transactions = add_order_value(transactions)

    # Drop helper column if present
    transactions = transactions.drop(columns=['desc_lengths'], errors='ignore')

    print("Saving to MySQL...")
    save_to_mysql(transactions, table_name="clean_transactions")

    print("✅ Pipeline complete.")


if __name__ == "__main__":
    INPUT_CSV = "data.csv"
    run_python_cleaning_pipeline(INPUT_CSV)


