create or replace function assert_eq(actual anyelement, expected anyelement, label text)
returns text language plpgsql as $$
begin
  if actual is not distinct from expected then
    return 'OK   -> ' || label;
  end if;
  raise exception 'ECHEC [%] : attendu "%", obtenu "%"', label, expected, actual;
end $$;

