-- Rôle applicatif. Sur Neon, créez-le depuis la console (Roles ->
-- New Role) ; ici on le fabrique pour pouvoir tester en local.
--
-- NOTE : 02_rls_and_import.sql fait ensuite `set local role
-- tablefinder_app` depuis cette même session pour simuler l'app. Ça ne
-- fonctionne que si le rôle courant peut endosser tablefinder_app —
-- vrai pour un superutilisateur Postgres local, PAS automatique pour
-- `neondb_owner` sur Neon si le rôle a été créé hors de cette session
-- (console/CLI Neon). Sur Neon, préférer une connexion directe avec
-- les identifiants tablefinder_app pour ces vérifications-là plutôt
-- que SET ROLE.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'tablefinder_app') then
    create role tablefinder_app login password 'test-only';
  end if;
end $$;

