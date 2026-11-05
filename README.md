# Motor Stock

A Flutter app for managing stock in a motorbike parts shop. Staff sign in, then add, edit and delete parts. Each part can have up to 3 photos. The backend is Supabase on the free plan: Auth, Postgres and Storage.

## 1. Set up Supabase (one time)

1. Create a free project at https://supabase.com.
2. Open **SQL Editor**, paste in the contents of [`supabase/schema.sql`](supabase/schema.sql) and click **Run**. This creates:
   - the `parts` and `part_images` tables, with a limit of 3 images per part
   - row-level security, so only signed-in users can read or change stock
   - the `part-images` storage bucket and its policies
   
   Then run these the same way, in order:
   - [`supabase/002_categories_brands_models.sql`](supabase/002_categories_brands_models.sql) adds the Category, Bike Brand and Bike Model dropdown lists with their starting values.
   - [`supabase/003_branches_stock_transfers.sql`](supabase/003_branches_stock_transfers.sql) adds shop branches (IBBAGAMUWA main, MELSIRIPURA), stock per branch and stock transfers. Existing quantities move to the main branch.
3. **Authentication → Sign In / Providers**: turn off **Allow new users to sign up**. Only you will be able to add staff accounts.
4. **Authentication → Users → Add user**: create an account (email and password) for each staff member.
5. **Project Settings → API Keys**: copy the project URL and the **publishable** key. Never put the `service_role` or secret key in the app.

## 2. Run the app

```bash
cp env.example.json env.json   # then fill in the URL and key
flutter pub get
flutter run --dart-define-from-file=env.json
```

`env.json` is in `.gitignore`.

## Structure

```
lib/
  main.dart                       Supabase init and auth gate
  theme.dart                      OSHU brand colours and logo widget
  models/part.dart                Part / PartImage models
  models/lookup.dart              category / brand / model list entries
  models/branch.dart              Branch / StockTransfer models
  services/parts_service.dart     CRUD, image upload and delete
  services/lookup_service.dart    add, rename, delete list entries
  services/branch_service.dart    branches, per-branch stock, transfers
  widgets/lookup_widgets.dart     dropdown, name dialog
  widgets/transfer_sheet.dart     move stock between branches
  screens/login_screen.dart
  screens/parts_list_screen.dart    branch selector, search, filters, quick +/- qty
  screens/part_form_screen.dart     add/edit part, stock per branch, up to 3 photos
  screens/transfers_screen.dart     transfer history
  screens/manage_lookups_screen.dart  categories, brands, models, branches
supabase/schema.sql                         base tables and storage
supabase/002_categories_brands_models.sql   dropdown lists
supabase/003_branches_stock_transfers.sql   branches, stock per branch, transfers
```

Photos are resized to a maximum of 1280 px at JPEG quality 75 when picked, so each is roughly 100–300 KB. At that size, the 1 GB free storage holds about 1,500 or more parts with 3 photos each.
