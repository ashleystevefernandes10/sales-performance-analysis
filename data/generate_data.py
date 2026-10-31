"""Generate a synthetic, deliberately messy retail transactions file (Superstore-style).

Run:  python3 data/generate_data.py   ->  data/sales_raw.csv
Replace sales_raw.csv with your own extract (same columns) to re-run the whole project.
"""
import numpy as np
import pandas as pd

rng = np.random.default_rng(42)

# region: (price multiplier, extra chance of heavy discounting)
regions = {"West": (1.00, 0.0), "East": (0.95, 0.0), "Central": (0.85, 0.10), "South": (0.70, 0.03)}
segments = {"Consumer": 0.52, "Corporate": 0.31, "Home Office": 0.17}
# category -> sub_category -> (typical list price, base margin)
catalog = {
    "Furniture": {"Chairs": (180, .06), "Tables": (420, -.03), "Bookcases": (260, .02), "Furnishings": (45, .14)},
    "Office Supplies": {"Paper": (25, .28), "Binders": (30, .20), "Storage": (95, .11), "Art": (18, .22), "Labels": (14, .30)},
    "Technology": {"Phones": (340, .17), "Accessories": (60, .24), "Copiers": (1400, .30), "Machines": (900, .04)},
}
states = {"West": ["California", "Washington", "Oregon"], "East": ["New York", "Pennsylvania", "Virginia"],
          "Central": ["Texas", "Illinois", "Ohio"], "South": ["Florida", "Georgia", "North Carolina"]}

n_cust = 700
cust = pd.DataFrame({
    "customer_id": [f"C{1000+i}" for i in range(n_cust)],
    "customer_name": [f"Customer {i:03d}" for i in range(n_cust)],
    "segment": rng.choice(list(segments), n_cust, p=list(segments.values())),
    "region": rng.choice(list(regions), n_cust, p=[.32, .28, .22, .18]),
})

rows, oid = [], 0
for m in pd.period_range("2021-01", "2024-12", freq="M"):
    t = (m.year - 2021) * 12 + m.month
    season = {11: 1.55, 12: 1.75, 9: 1.25, 3: 1.1, 1: 0.75, 2: 0.78}.get(m.month, 1.0)
    n_orders = int(95 * (1.012 ** t) * season * rng.uniform(.93, 1.07))
    for _ in range(n_orders):
        oid += 1
        c = cust.iloc[rng.integers(n_cust)]
        od = m.to_timestamp() + pd.Timedelta(days=int(rng.integers(0, m.days_in_month)))
        sd = od + pd.Timedelta(days=int(rng.integers(1, 8)))
        ship_mode = rng.choice(["Standard Class", "Second Class", "First Class", "Same Day"], p=[.6, .2, .15, .05])
        for _ in range(rng.choice([1, 2, 3, 4], p=[.5, .28, .15, .07])):
            cat = rng.choice(list(catalog))
            sub = rng.choice(list(catalog[cat]))
            price, base_margin = catalog[cat][sub]
            qty = int(rng.choice(range(1, 9), p=[.3, .25, .17, .11, .07, .05, .03, .02]))
            rmult, dextra = regions[c.region]
            disc = float(rng.choice([0, 0, 0, .1, .15, .2, .3, .4, .5, .6, .7],
                                    p=[.30, .15, .10, .07, .05, .10, .07, .05, .04, .04, .03]))
            if rng.random() < dextra * 2:
                disc = max(disc, float(rng.choice([.3, .4, .5])))
            list_price = price * rng.uniform(.85, 1.15)
            sales = round(list_price * qty * (1 - disc), 2)
            margin = base_margin + rng.normal(0, .03) - 0.55 * disc * (disc > .2) - 0.10 * disc
            profit = round(sales * margin - rng.uniform(0, 3), 2)
            rows.append([f"CA-{m.year}-{oid:06d}", od, sd, c.customer_id, c.customer_name, c.segment, c.region,
                         rng.choice(states[c.region]), cat, sub, f"{sub} item {rng.integers(1, 60):02d}",
                         sales, qty, disc, profit, ship_mode])

df = pd.DataFrame(rows, columns=["order_id", "order_date", "ship_date", "customer_id", "customer_name", "segment",
                                 "region", "state", "category", "sub_category", "product_name", "sales", "quantity",
                                 "discount", "profit", "ship_mode"])

# ---- inject realistic data-quality problems (to be fixed in sql/02_clean.sql) ----
df["order_date"] = df["order_date"].dt.strftime("%Y-%m-%d")
df["ship_date"] = df["ship_date"].dt.strftime("%Y-%m-%d")
idx = rng.choice(len(df), int(.02 * len(df)), replace=False)            # alternative date format
df.loc[idx, "order_date"] = pd.to_datetime(df.loc[idx, "order_date"]).dt.strftime("%d/%m/%Y")
idx = rng.choice(len(df), int(.03 * len(df)), replace=False)            # casing / whitespace
df.loc[idx, "region"] = df.loc[idx, "region"].map(lambda s: " " + s.upper() + " ")
idx = rng.choice(len(df), int(.02 * len(df)), replace=False)
df.loc[idx, "category"] = df.loc[idx, "category"].str.lower()
idx = rng.choice(len(df), int(.01 * len(df)), replace=False); df.loc[idx, "discount"] = np.nan   # missing discount
idx = rng.choice(len(df), int(.004 * len(df)), replace=False); df.loc[idx, "sales"] = np.nan      # missing sales
idx = rng.choice(len(df), int(.003 * len(df)), replace=False); df.loc[idx, "quantity"] = 0         # invalid qty
df = pd.concat([df, df.sample(int(.015 * len(df)), random_state=1)]).sample(frac=1, random_state=7)  # duplicates

df.to_csv("data/sales_raw.csv", index=False)
print("rows written:", df.shape[0])
