-- Paid custom finger-soccer team: one unlock per account, crest replacement is free afterwards.
insert into public.nx_catalog(item_id, price, currency, kind, name, active)
values ('fs_custom_team', 1000, 'gems', 'finger_soccer_custom_team', 'Custom Team', true)
on conflict (item_id) do update set price = 1000, currency = 'gems', kind = 'finger_soccer_custom_team', name = 'Custom Team', active = true, updated_at = now();
