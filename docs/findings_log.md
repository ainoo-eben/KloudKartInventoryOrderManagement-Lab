# Findings Log

## Schema inventory

Source: `data/schema.sql` (reviewed without modification).

### `categories`

| Column | Type | Primary key |
|---|---|---|
| `category_id` | `integer` | Yes |
| `category_name` | `text` | No |
| `parent_id` | `integer` | No |

`parent_id` is described as a self-reference, but no foreign key is defined.

### `products`

| Column | Type | Primary key |
|---|---|---|
| `product_id` | `integer` | Yes |
| `product_name` | `text` | No |
| `category_id` | `integer` | No |
| `price` | `numeric(12,2)` | No |
| `stock_quantity` | `integer` | No |
| `created_at` | `timestamp` | No |

### `customers`

| Column | Type | Primary key |
|---|---|---|
| `customer_id` | `integer` | Yes |
| `full_name` | `text` | No |
| `email` | `text` | No |
| `phone` | `text` | No |
| `city` | `text` | No |
| `registered_at` | `timestamp` | No |

The schema does not declare `email` unique.

### `orders`

| Column | Type | Primary key |
|---|---|---|
| `order_id` | `integer` | Yes |
| `customer_id` | `integer` | No |
| `order_date` | `timestamp` | No |
| `status` | `text` | No |
| `total_amount` | `numeric(12,2)` | No |

### `order_items`

| Column | Type | Primary key |
|---|---|---|
| `order_item_id` | `integer` | Yes |
| `order_id` | `integer` | No |
| `product_id` | `integer` | No |
| `quantity` | `integer` | No |
| `unit_price` | `numeric(12,2)` | No |

### `inventory_log`

| Column | Type | Primary key |
|---|---|---|
| `log_id` | `integer` | Yes |
| `product_id` | `integer` | No |
| `change_qty` | `integer` | No |
| `reason` | `text` | No |
| `created_at` | `timestamp` | No |
| `note` | `text` | No |

## What the database checks (and what it does not)

The schema gives every table a primary key: the ID column marked “Yes” above. A primary key is the table's unique record identifier. The database will not allow two rows in the same table to share that ID.

The schema does **not** make the database check that related records actually exist:

- A product's `category_id` does not have to match an ID in `categories`.
- An order's `customer_id` does not have to match an ID in `customers`.
- An order item's `order_id` and `product_id` do not have to match existing orders and products.
- An inventory log's `product_id` does not have to match an existing product.
- A category's `parent_id` does not have to match another category.

These columns look like links between records, but the database does not enforce those links. As a result, incorrect or orphaned references could be saved.

The database also has no extra rules to reject invalid values. For example, it does not prevent stock or an order-item quantity from being negative, and it does not limit order status or inventory-log reason to approved values.

There are no separately defined indexes for looking up or sorting data. The database creates an index for each primary key automatically, but the schema adds no other indexes. Searches using other columns may therefore take longer as the tables grow.

## Load script notes

### What `load.sql` is for

The schema script creates the empty tables; the load script fills those tables with the rows from the CSV files. After loading, it asks PostgreSQL to refresh its table statistics and prints a row count for each table. Run it only after the database and tables have been created.

### Answers from `data/load.sql`

1. **How it reads the CSVs:** It uses PostgreSQL's `\copy` command. This reads each CSV from the computer running `psql` (the client), rather than requiring the database server or container to access those files directly.
2. **CSV paths:** The paths are relative, not absolute: `data/categories.csv`, `data/products.csv`, `data/customers.csv`, `data/orders.csv`, `data/order_items.csv`, and `data/inventory_log.csv`. They are resolved from the directory where `psql` is run.
3. **Database creation:** The script does not create a database or tables. A database must already exist, and `schema.sql` must have created its tables first.

**Path mismatch to resolve before running:** The supplied CSVs are currently in `data/csv/` (for example, `data/csv/categories.csv`), but `load.sql` refers to `data/categories.csv`. As written, those paths will not find the supplied files from the project root. The run instructions at the top of `load.sql` also assume a working directory; check both the working directory and CSV locations before loading.
