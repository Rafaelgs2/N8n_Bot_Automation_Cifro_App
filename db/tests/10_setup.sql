-- Fixtures. Signing up fires the real trigger, which creates the profile and the default categories.
\set UA '''aaaaaaaa-0000-4000-8000-00000000000a'''
\set UB '''aaaaaaaa-0000-4000-8000-00000000000b'''
\set UC '''aaaaaaaa-0000-4000-8000-00000000000c'''
\set UE '''aaaaaaaa-0000-4000-8000-00000000000e'''
\set A1 '''ba000000-0000-4000-8000-000000000001'''
\set A2 '''ba000000-0000-4000-8000-000000000002'''
\set B1 '''bb000000-0000-4000-8000-000000000001'''
\set C1 '''bc000000-0000-4000-8000-000000000001'''
\set E1 '''be000000-0000-4000-8000-000000000001'''

-- A has two accounts, B has one, C only has an account whose opening balance date is in the future,
-- and E has one that a test removes later.
insert into auth.users (id) values (:UA), (:UB), (:UC), (:UE);

set role authenticated;
select t.set_accounts(:UA, jsonb_build_array(
  t.account(:A1, 'Conta A', 'salary', '2026-01-01', false, 0),
  t.account(:A2, 'Conta A2', 'other', '2026-01-01', false, 1)));
select t.set_accounts(:UB, jsonb_build_array(t.account(:B1, 'Conta B', 'salary', '2026-01-01')));
select t.set_accounts(:UC, jsonb_build_array(t.account(:C1, 'Conta futura', 'other', '2099-01-01')));
select t.set_accounts(:UE, jsonb_build_array(t.account(:E1, 'Conta E', 'other', '2026-01-01')));
select t.add_expense_category(:UA, 'c9000000-0000-4000-8000-000000000001', 'C++ (curso)', 'education');
reset role;

select t.eq('SETUP', 'o cadastro cria as 10 categorias padrão', (select count(*)::text from public.categories where user_id = :UB), '10');
select t.eq('SETUP', 'a categoria criada pelo app também existe', (select count(*)::text from public.categories where user_id = :UA and name = 'C++ (curso)'), '1');
